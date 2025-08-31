// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./SHIBLiquidityManager.sol";
import "./IMeme.sol";

contract MemePenguin is ERC20,IMeme {

    // 代币税比例 默认5%
    uint256 public taxRate = 5;
    uint256 public constant TAX_RATE_DENOMINATOR = 100;
    //最大交易金额
    uint256 public maxTradeAmount;
    //最多交易次数
    uint256 public maxTradeCount;

    // 记录每日交易次数
    mapping(address userAddr => mapping(uint256 currentDay => uint256 tradeCount)) private _dailyTrades;
    mapping(address userAddr => uint256 lastTradeDay) private _lastTradeDay;

    // 豁免税费的映射
    mapping(address => bool) private _isExcludedFromFee;

    //owner
    address public owner;
    
    // 流动性管理器合约地址
    address public liquidityManager;

    //交易次数超限事件日志
    event DailyTradeLimitExceeded(address indexed user, uint256 attemptCount);
    // 税费添加到流动性池事件
    event TaxAddedToLiquidity(uint256 taxAmount);

    event ExcludedFromFee(address indexed  addr);
    event IncludedInFee(address indexed  addr);

    constructor() ERC20("MemePenguin", "PGN") {
        owner = msg.sender;
        // 100万亿代币
        _mint(msg.sender, 100000000 * (10 ** decimals()));
        // 默认豁免以下地址
        _isExcludedFromFee[msg.sender] = true; // Owner
        _isExcludedFromFee[address(this)] = true; // 合约自身
    }



    modifier onlyOwner {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

        

    // 添加初始化函数
    function setLiquidityManager(address _liquidityManager) external onlyOwner {
        require(liquidityManager == address(0), "Already initialized");
        liquidityManager = _liquidityManager;
        _isExcludedFromFee[_liquidityManager] = true;
    }

    //调节代币税率
    function setTaxRate(uint256 _taxRate) external onlyOwner {
        taxRate = _taxRate;
    }


    function _tradeWithTax(address from, address to, uint256 amount) internal { 
        // 如果任何一方豁免税费，直接转账
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            _transfer(from, to, amount);
        }else{ 

            //单笔交易最大额度
            require(amount <= maxTradeAmount, "ERC20: transfer amount exceeds the maximum limit");
            // 检查每日交易限制（排除mint和burn）
            if (from != address(0) && to != address(0)) {
                _checkDailyTradeLimit(from);
            }
            //税金
            uint256 taxAmount = amount * taxRate / TAX_RATE_DENOMINATOR; 
            //实际转账金额
            uint256 transferAmount = amount - taxAmount;
            // 执行转账（扣除税费）
            _transfer(from, to, transferAmount);
            
            // 将税费转移到流动性池
            _transfer(from, liquidityManager, taxAmount);
            
            // 调用流动性管理器的自动添加流动性功能
            if (liquidityManager != address(0)) {
                // 确保合约有足够的配额
                if (IERC20(address(this)).allowance(address(this), liquidityManager) < taxAmount) {
                    IERC20(address(this)).approve(liquidityManager, type(uint256).max);
                }
                
                // 调用自动添加流动性功能
                SHIBLiquidityManager(liquidityManager).addAutoLiquidity(0);
            }
            
            // 发出事件
            emit TaxAddedToLiquidity(taxAmount);
        } 
    }

    //代币税功能：实现交易税机制，对每笔代币交易征收一定比例的税费，并将税费分配至流动性池
    function transfer(address to, uint256 amount) 
        public 
        virtual 
        override 
        returns (bool) {
    
        require(amount > 0, "ERC20: transfer amount must be greater than zero");

        address from = _msgSender();

        _tradeWithTax(from, to, amount);
        
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {

        require(amount > 0, "ERC20: transfer amount must be greater than zero");

        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        
        _tradeWithTax(from, to, amount);
        
        return true;
    }

    /**
     * 交易限制功能
     * 设置合理的交易限制，如单笔交易最大额度、每日交易次数限制等，防止恶意操纵市场。
     */
    function setTradeLimit(uint256 _maxTradeAmount, uint256 _maxTradeCount) external onlyOwner {
        maxTradeAmount = _maxTradeAmount;
        maxTradeCount = _maxTradeCount;
    }

    /**
     * 检查每日交易限制
     */
    function _checkDailyTradeLimit(address user) internal {
        uint256 currentDay = block.timestamp / 1 days;
        
        // 如果是新的一天，重置计数器
        if (_lastTradeDay[user] != currentDay) {
            _dailyTrades[user][currentDay] = 0;
            _lastTradeDay[user] = currentDay;
        }
        
        // 增加交易计数
        _dailyTrades[user][currentDay] += 1;
        
        // 检查是否超过限制
        if (_dailyTrades[user][currentDay] > maxTradeCount) {
            emit DailyTradeLimitExceeded(user, _dailyTrades[user][currentDay]);
            revert("Daily trade limit exceeded");
        }
    }



    /**
     * 获取用户今日交易次数
     */
    function getTodayTradeCount(address user) public view returns (uint256) {
        uint256 currentDay = block.timestamp / 1 days;
        return _dailyTrades[user][currentDay];
    }

    /**
     * 获取今日剩余交易次数
     */
    function getRemainingTrades(address user) public view returns (uint256) {
        uint256 todayCount = getTodayTradeCount(user);
        return todayCount >= maxTradeCount ? 0 : maxTradeCount - todayCount;
    }

    /**
     * 获取每日交易限制
     */
    function getDailyTradeLimit() public view returns (uint256) {
        return maxTradeCount;
    }

    /**
     * 获取每日单笔最大交易金额
     */
    function getDailyMaxTradeAmount() public view returns (uint256) {
        return maxTradeAmount;
    }

    // 豁免税费
    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;
        emit ExcludedFromFee(account);
    }
    
    // 恢复收费
    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
        emit IncludedInFee(account);
    }
    
    //是否豁免
    function isExcludedFromFee(address account) external view returns(bool) {
        return _isExcludedFromFee[account];
    }
}