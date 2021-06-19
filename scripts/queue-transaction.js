const hre = require("hardhat");

const GOVERNOR_ALPHA_ABI = require('../artifacts/contracts/GovernorAlpha.sol/GovernorAlpha.json').abi;
const TIMELOCK_ABI = require('../artifacts/contracts/Timelock.sol/Timelock.json').abi;

// Timelock deployed to: 0x2b9C24A5644Ed074360517d6797acAEC6bdF59Ee
// GovernorAlpha deployed to: 0xad3CB8d7B31b2f9619Fe82ae93DF5C041fFf87cE
// Timelock admin 0xad3CB8d7B31b2f9619Fe82ae93DF5C041fFf87cE
// Governor alpha timelock 0x2b9C24A5644Ed074360517d6797acAEC6bdF59Ee

const GOVERNOR_ALPHA_ADDRESS = '0x855d7AFD67Feca508efc9a5Ebe22139BCe629522';

async function main() {
  const [pfxAdmin, pfxDev, anUser] = await hre.ethers.getSigners();

  // const governorAlpha = new hre.ethers.Contract('0x2752EEc6c227A2dD51b998D52eAb66F15a0eD0b1', GOVERNOR_ALPHA_ABI)
  //   .connect(pfxDev);

  // const t = await governorAlpha.execute(1)
  // console.log(t)

  await new hre.ethers.Contract('0xE54f7C0211e3eBf5459c3112A0204c902446C98B', TIMELOCK_ABI)
    .connect(pfxAdmin)
    .delay()
    .then(delay => console.log('delay', delay.to))
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
