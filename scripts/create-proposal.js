const hre = require("hardhat");

const GOVERNOR_ALPHA_ABI = require('../artifacts/contracts/GovernorAlpha.sol/GovernorAlpha.json').abi;
const TIMELOCK_ABI = require('../artifacts/contracts/Timelock.sol/Timelock.json').abi

// Timelock deployed to: 0x2b9C24A5644Ed074360517d6797acAEC6bdF59Ee
// GovernorAlpha deployed to: 0xad3CB8d7B31b2f9619Fe82ae93DF5C041fFf87cE
// Timelock admin 0xad3CB8d7B31b2f9619Fe82ae93DF5C041fFf87cE
// Governor alpha timelock 0x2b9C24A5644Ed074360517d6797acAEC6bdF59Ee

const GOVERNOR_ALPHA_ADDRESS = '0xad3CB8d7B31b2f9619Fe82ae93DF5C041fFf87cE';
const TIMELOCK_ADDRESS = '0x2b9C24A5644Ed074360517d6797acAEC6bdF59Ee';

async function main() {
  const [pfxAdmin, _, anUser] = await hre.ethers.getSigners();

  const governorAlpha = new hre.ethers.Contract(GOVERNOR_ALPHA_ADDRESS, GOVERNOR_ALPHA_ABI);

  const target = TIMELOCK_ADDRESS;
  const value = 0;
  const sig = 'setDelay(uint256)';
  const callData = ethers.utils.defaultAbiCoder.encode(['uint256'], [3 * 60]);
  const description = '\nIncrease proposal queuing time\nIncrease proposal queuing delay from 2 days to 3 days before execution'

  await governorAlpha.connect(pfxAdmin)
    .propose([target], [value], [sig], [callData], description);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
