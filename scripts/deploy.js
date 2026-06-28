const { ethers, network } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Network  :", network.name);
  console.log("Deployer :", deployer.address);
  console.log("Balance  :", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const CharityVault = await ethers.getContractFactory("CharityVault");
  const vault = await CharityVault.deploy();
  await vault.waitForDeployment();

  const address = await vault.getAddress();
  console.log("CharityVault deployed to:", address);
  console.log("\nUpdate CONTRACT_ADDRESS in frontend/index.html");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });

