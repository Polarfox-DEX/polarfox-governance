const hre = require("hardhat");

async function main() {
  const [admin] = await hre.ethers.getSigners();

  const currentNonce = await admin.getTransactionCount();


  const futureGovernorAlphaAddress = await ethers.utils.getContractAddress({
    from: admin.address,
    nonce: currentNonce + 2 // (PFX + Timelock)
  });
  console.log('futureGovernorAlphaAddress', futureGovernorAlphaAddress)

  // Deploy PFX, sending the total supply to the admin
  const Pfx = await hre.ethers.getContractFactory("Pfx");
  const pfx = await Pfx.deploy(admin.address);
  console.log('Pfx deployed to:', pfx.address);

  // Deploy Timelock
  const TWO_DAYS_IN_SECONDS = 60 * 60 * 24 * 2;
  const Timelock = await hre.ethers.getContractFactory('Timelock');
  const timelock = await Timelock.deploy(futureGovernorAlphaAddress, TWO_DAYS_IN_SECONDS);
  console.log('Timelock deployed to:', timelock.address);

  // Deploy GovernorAlpha
  const GovernorAlpha = await hre.ethers.getContractFactory('GovernorAlpha');
  const governorAlpha = await GovernorAlpha.deploy(timelock.address, '0x90E487E9a08fF29B2F97ECd0eD73886692dF70D1');
  console.log('GovernorAlpha deployed to:', governorAlpha.address);

  console.log('Timelock admin', await timelock.admin());
  console.log('Governor alpha timelock', await governorAlpha.timelock());
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
