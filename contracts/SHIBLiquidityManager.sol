// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./IMeme.sol";

contract SHIBLiquidityManager is Ownable {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public immutable router;
    IUniswapV2Factory public immutable factory;
    IMeme public immutable shibToken; // 您的SHIB风格代币
    IERC20 public immutable pairedToken; // 通常为WETH或USDT

    // 自动LP接收地址（通常是死地址或社区金库）
    address public constant autoLpReceiver = 0xBd3E6b5e15C8766778De15Ac603880b5FB0a057f;

    event LiquidityAdded(address indexed user, uint256 shibAmount, uint256 pairedAmount, uint256 liquidity);
    event LiquidityRemoved(address indexed user, uint256 liquidity, uint256 shibAmount, uint256 pairedAmount);
    event AutoLiquidityAdded(uint256 shibAmount, uint256 pairedAmount, uint256 liquidity);

    constructor(
        address _router,
        address _shibToken,
        address _pairedToken
    ) Ownable(msg.sender){
        router = IUniswapV2Router02(_router);
        factory = IUniswapV2Factory(router.factory());
        shibToken = IMeme(_shibToken);
        pairedToken = IERC20(_pairedToken);
        
        // 永久豁免本合约的交易费
        IMeme(_shibToken).excludeFromFee(address(this));
    }

    /**
     * 为SHIB风格代币添加流动性（豁免税费）
     */
    function addShibLiquidity(
        uint256 shibAmount,
        uint256 pairedAmountDesired,
        uint256 pairedAmountMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // 将用户的代币转移到本合约
        IERC20(address(shibToken)).safeTransferFrom(msg.sender, address(this), shibAmount);
        pairedToken.safeTransferFrom(msg.sender, address(this), pairedAmountDesired);

        // 授权路由器使用代币
        _approveTokensIfNeeded(address(shibToken), address(router), shibAmount);
        _approveTokensIfNeeded(address(pairedToken), address(router), pairedAmountDesired);

        // 临时豁免用户税费（如果是移除流动性后再次添加）
        bool wasExcluded = shibToken.isExcludedFromFee(msg.sender);
        if (!wasExcluded) {
            shibToken.excludeFromFee(msg.sender);
        }

        // 添加流动性
        (amountA, amountB, liquidity) = router.addLiquidity(
            address(shibToken),
            address(pairedToken),
            shibAmount,
            pairedAmountDesired,
            shibAmount, // 由于豁免税费，最小数量可以等于输入数量
            pairedAmountMin,
            to,
            deadline
        );

        // 恢复用户税费状态（如果不是原本就豁免的）
        if (!wasExcluded) {
            shibToken.includeInFee(msg.sender);
        }

        // 返还剩余代币
        _refundRemainingTokens(shibAmount, amountA, pairedAmountDesired, amountB);

        emit LiquidityAdded(msg.sender, amountA, amountB, liquidity);
    }

    /**
     * 移除SHIB代币的流动性（豁免税费）
     */
    function removeShibLiquidity(
        uint256 liquidity,
        uint256 shibAmountMin,
        uint256 pairedAmountMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        address pair = factory.getPair(address(shibToken), address(pairedToken));
        require(pair != address(0), "Pair does not exist");

        // 转移LP代币并授权
        IERC20(pair).safeTransferFrom(msg.sender, address(this), liquidity);
        _approveTokensIfNeeded(pair, address(router), liquidity);

        // 临时豁免用户税费
        bool wasExcluded = shibToken.isExcludedFromFee(msg.sender);
        if (!wasExcluded) {
            shibToken.excludeFromFee(msg.sender);
        }

        // 移除流动性
        (amountA, amountB) = router.removeLiquidity(
            address(shibToken),
            address(pairedToken),
            liquidity,
            shibAmountMin,
            pairedAmountMin,
            address(this), // 先收到本合约，避免用户被收费
            deadline
        );

        // 将代币转给用户（此时已无税费）
        IERC20(address(shibToken)).safeTransfer(to, amountA);
        pairedToken.safeTransfer(to, amountB);

        // 恢复用户税费状态
        if (!wasExcluded) {
            shibToken.includeInFee(msg.sender);
        }

        emit LiquidityRemoved(msg.sender, liquidity, amountA, amountB);
    }

    /**
     * 自动添加流动性功能（由合约调用，用于将积累的税费转为LP）
     */
    function addAutoLiquidity(uint256 minPairedTokenAmount) external onlyOwner {
        uint256 shibBalance = IERC20(address(shibToken)).balanceOf(address(this));
        uint256 pairedBalance = pairedToken.balanceOf(address(this));
        
        require(shibBalance > 0, "Insufficient SHIB balance");

        // 如果没有 paired token 余额，则需要兑换一半的 SHIB 为 paired token
        if (pairedBalance < minPairedTokenAmount) {
            uint256 shibToSwap = shibBalance / 2;
            require(shibToSwap > 0, "Insufficient SHIB to swap");
            
            // 兑换一半的 SHIB 为 paired token
            _swapShibForPairedToken(shibToSwap);
            
            // 更新余额
            shibBalance = IERC20(address(shibToken)).balanceOf(address(this));
            pairedBalance = pairedToken.balanceOf(address(this));
        }

        require(pairedBalance >= minPairedTokenAmount, "Insufficient paired token balance after swap");

        _approveTokensIfNeeded(address(shibToken), address(router), shibBalance);
        _approveTokensIfNeeded(address(pairedToken), address(router), pairedBalance);

        router.addLiquidity(
            address(shibToken),
            address(pairedToken),
            shibBalance,
            pairedBalance,
            0,
            minPairedTokenAmount,
            autoLpReceiver, // 发送到死地址锁定流动性
            block.timestamp + 1 hours
        );

        emit AutoLiquidityAdded(shibBalance, pairedBalance, IERC20(factory.getPair(address(shibToken), address(pairedToken))).balanceOf(autoLpReceiver));
    }

    // ==================== 内部工具函数 ====================
    function _approveTokensIfNeeded(address token, address spender, uint256 amount) internal {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).approve(spender, amount);
        }
    }

    function _refundRemainingTokens(
        uint256 shibInput,
        uint256 shibUsed,
        uint256 pairedInput,
        uint256 pairedUsed
    ) internal {
        if (shibInput > shibUsed) {
            IERC20(address(shibToken)).safeTransfer(msg.sender, shibInput - shibUsed);
        }
        if (pairedInput > pairedUsed) {
            pairedToken.safeTransfer(msg.sender, pairedInput - pairedUsed);
        }
    }

    /**
     * 将SHIB代币兑换为配对代币
     */
    function _swapShibForPairedToken(uint256 shibAmount) internal {
        _approveTokensIfNeeded(address(shibToken), address(router), shibAmount);
        
        address[] memory path = new address[](2);
        path[0] = address(shibToken);
        path[1] = address(pairedToken);
        
        router.swapExactTokensForTokens(
            shibAmount,
            0, // 可以考虑设置最小兑换量以提高安全性
            path,
            address(this),
            block.timestamp + 1 hours
        );
    }

    // 紧急提取代币（仅Owner）
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}