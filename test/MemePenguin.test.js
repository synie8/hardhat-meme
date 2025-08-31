const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MemePenguin", function () {
  let MemePenguin;
  let memePenguin;
  let owner;
  let user1;
  let user2;
  let liquidityManager;

  beforeEach(async function () {
    [owner, user1, user2, liquidityManager] = await ethers.getSigners();

    console.log("owner  **************** ", owner);
    console.log("user1  **************** ", user1);
    console.log("user2  **************** ", user2);
    console.log("liquidityManager  **************** ", liquidityManager);

    // 部署代币合约
    MemePenguin = await ethers.getContractFactory("MemePenguin");
    memePenguin = await MemePenguin.deploy();
    await memePenguin.waitForDeployment();

    const owner1 = await memePenguin.owner();
    console.log("owner  **************** ", owner.address);
    console.log("owner1  **************** ", owner1);

    // 初始化流动性管理器
    await memePenguin.setLiquidityManager(liquidityManager.address);

    // 设置交易限制
    await memePenguin.setTradeLimit(
      ethers.parseEther("1000000"), // 100万代币
      10 // 10次/天
    );

    // 给测试用户转账
    const transferAmount = ethers.parseEther("10000");
    await memePenguin.transfer(user1.address, transferAmount);
    await memePenguin.transfer(user2.address, transferAmount);
  });

  describe("Deployment", function () {


    it("Should set the right owner", async function () {
      expect(await memePenguin.owner()).to.equal(owner.address);
    });
    
    it("Should assign total supply to owner", async function () {
      const ownerBalance = await memePenguin.balanceOf(owner.address);
      //上面转移了2次10000，所以这里减去2*10000
      expect(await memePenguin.totalSupply()-ethers.parseEther("20000")).to.equal(ownerBalance);
    });

    it("Should set liquidity manager correctly", async function () {
      expect(await memePenguin.liquidityManager()).to.equal(liquidityManager.address);
    });
  });

 
  describe("Tax Mechanism", function () {
    it("Should charge tax on transfers", async function () {
      const amount = ethers.parseEther("100");
      const initialBalance = await memePenguin.balanceOf(user1.address);
      
      await memePenguin.connect(user1).transfer(user2.address, amount);
      
      const finalBalance = await memePenguin.balanceOf(user1.address);
      const expectedDeduction = amount + amount * 5 / 100 ; // 5% tax
      
      expect(initialBalance - finalBalance ).to.equal(expectedDeduction);
    });

    it("Should exempt liquidity manager from tax", async function () {
      const amount = ethers.parseEther("100");
      const initialBalance = await memePenguin.balanceOf(owner.address);
      
      // 从owner转账到流动性管理器（应豁免税费）
      await memePenguin.transfer(liquidityManager.address, amount);
      
      const finalBalance = await memePenguin.balanceOf(owner.address);
      expect(initialBalance - finalBalance ).to.equal(amount); // 无税费扣除
    });
  });
 /*
  describe("Trade Limits", function () {
    it("Should enforce daily trade limit", async function () {
      const amount = ethers.utils.parseEther("10");
      
      // 进行10次交易（达到限制）
      for (let i = 0; i < 10; i++) {
        await memePenguin.connect(user1).transfer(user2.address, amount);
      }
      
      // 第11次交易应该失败
      await expect(
        memePenguin.connect(user1).transfer(user2.address, amount)
      ).to.be.revertedWith("Daily trade limit exceeded");
    });

    it("Should reset daily limit after 24 hours", async function () {
      const amount = ethers.utils.parseEther("10");
      
      // 达到交易限制
      for (let i = 0; i < 10; i++) {
        await memePenguin.connect(user1).transfer(user2.address, amount);
      }
      
      // 时间前进1天
      await ethers.provider.send("evm_increaseTime", [86400]);
      await ethers.provider.send("evm_mine");
      
      // 现在应该可以再次交易
      await expect(
        memePenguin.connect(user1).transfer(user2.address, amount)
      ).to.not.be.reverted;
    });
  });

  describe("Ownership Functions", function () {
    it("Should allow owner to change tax rate", async function () {
      await memePenguin.setTaxRate(10); // 10% tax
      expect(await memePenguin.taxRate()).to.equal(10);
    });

    it("Should not allow non-owner to change tax rate", async function () {
      await expect(
        memePenguin.connect(user1).setTaxRate(10)
      ).to.be.revertedWith("Only owner can call this function.");
    });

    it("Should allow owner to exclude addresses from fee", async function () {
      await memePenguin.excludeFromFee(user1.address);
      expect(await memePenguin.isExcludedFromFee(user1.address)).to.be.true;
    });
  });

  describe("Liquidity Manager", function () {
    it("Should transfer tax to liquidity manager", async function () {
      const amount = ethers.utils.parseEther("100");
      const initialManagerBalance = await memePenguin.balanceOf(liquidityManager.address);
      
      await memePenguin.connect(user1).transfer(user2.address, amount);
      
      const finalManagerBalance = await memePenguin.balanceOf(liquidityManager.address);
      const taxAmount = amount.mul(5).div(100);
      
      expect(finalManagerBalance.sub(initialManagerBalance)).to.equal(taxAmount);
    }); 
  
  });  */
 
});