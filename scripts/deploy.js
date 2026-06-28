import hre from "hardhat";
const { ethers, network } = hre;

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("─".repeat(50));
  console.log("Network  :", network.name);
  console.log("Deployer :", deployer.address);
  console.log("Balance  :", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");
  console.log("─".repeat(50));

  const CharityVault = await ethers.getContractFactory("CharityVault");
  const vault = await CharityVault.deploy();
  await vault.waitForDeployment();

  const address = await vault.getAddress();
  console.log("CharityVault deployed to:", address);

  if (network.name !== "hardhat" && network.name !== "localhost") {
    console.log("\nWaiting 10s before verification...");
    await new Promise((r) => setTimeout(r, 10_000));
    try {
      await hre.run("verify:verify", { address, constructorArguments: [] });
      console.log("Verified on Basescan ✓");
    } catch (e) {
      console.warn("Verification failed:", e.message);
    }
  }

  console.log("\n✅ Done. Update CONTRACT_ADDRESS in frontend/index.html");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
