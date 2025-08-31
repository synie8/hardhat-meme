const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // 1. 部署 MemePenguin 代币合约
  console.log("\n1. Deploying MemePenguin token...");
  const MemePenguin = await ethers.getContractFactory("MemePenguin");
  const memePenguin = await MemePenguin.deploy();
  await memePenguin.deployed();
  console.log("MemePenguin deployed to:", memePenguin.address);

  // 2. 部署 SHIBLiquidityManager 流动性管理器
  console.log("\n2. Deploying SHIBLiquidityManager...");
  
  // Sepolia 测试网地址（需要根据实际网络修改）
  const UNISWAP_ROUTER = "0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008";
  const WETH = "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14";
  
  const SHIBLiquidityManager = await ethers.getContractFactory("SHIBLiquidityManager");
  const liquidityManager = await SHIBLiquidityManager.deploy(
    UNISWAP_ROUTER,
    memePenguin.address,
    WETH
  );
  await liquidityManager.deployed();
  console.log("SHIBLiquidityManager deployed to:", liquidityManager.address);

  // 3. 初始化代币合约
  console.log("\n3. Initializing token with liquidity manager...");
  const setManagerTx = await memePenguin.setLiquidityManager(liquidityManager.address);
  await setManagerTx.wait();
  console.log("Liquidity manager set in token contract");

  // 4. 设置交易限制
  console.log("\n4. Setting trade limits...");
  const setLimitTx = await memePenguin.setTradeLimit(
    ethers.utils.parseEther("1000000"), // 最大交易量: 100万代币
    10 // 每日最多交易10次
  );
  await setLimitTx.wait();
  console.log("Trade limits set");

  // 5. 验证设置
  console.log("\n5. Verifying configuration...");
  const isManagerExcluded = await memePenguin.isExcludedFromFee(liquidityManager.address);
  console.log("Liquidity manager excluded from fee:", isManagerExcluded);

  const maxTradeAmount = await memePenguin.getDailyMaxTradeAmount();
  const maxTradeCount = await memePenguin.getDailyTradeLimit();
  console.log("Max trade amount:", ethers.utils.formatEther(maxTradeAmount), "PGN");
  console.log("Max trade count:", maxTradeCount.toString());

  console.log("\n=== Deployment Complete ===");
  console.log("MemePenguin Token:", memePenguin.address);
  console.log("Liquidity Manager:", liquidityManager.address);
  console.log("Owner:", deployer.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });