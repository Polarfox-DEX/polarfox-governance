const hre = require("hardhat");
const { PFX } = require('./governanceConstants')

async function main() {
  const [admin] = await hre.ethers.getSigners();
  
  const chainId = await admin.getChainId()

  const currentNonce = await admin.getTransactionCount();


  const futureGovernorAlphaAddress = await hre.ethers.utils.getContractAddress({
    from: admin.address,
    nonce: currentNonce + 1 // (Timelock)
  });
  console.log('futureGovernorAlphaAddress', futureGovernorAlphaAddress)

  // Deploy PFX, sending the total supply to the admin
  // const Pfx = await hre.ethers.getContractFactory("Pfx");
  // const pfx = await Pfx.deploy(admin.address);
  // console.log('Pfx deployed to:', pfx.address);

  // Deploy Timelock
  const TWO_DAYS_IN_SECONDS = 60 * 60 * 24 * 2;
  const Timelock = await hre.ethers.getContractFactory('Timelock');
  const timelock = await Timelock.deploy(futureGovernorAlphaAddress, TWO_DAYS_IN_SECONDS);
  console.log('Timelock deployed to:', timelock.address);

  // Deploy GovernorAlpha
  const GovernorAlpha = await hre.ethers.getContractFactory('GovernorAlpha');
  const governorAlpha = await GovernorAlpha.deploy(timelock.address, PFX[chainId]);
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
