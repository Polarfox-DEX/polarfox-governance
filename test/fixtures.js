const chai = require('chai');
const { expect } = chai;
const { Contract } = require('ethers');
const { solidity, deployContract } = require('ethereum-waffle');

const { TWO_DAYS } = require('./utils');

const Pfx = require('../artifacts/contracts/pfx/PFX.sol/Pfx.json');
const Timelock = require('../artifacts/contracts/Timelock.sol/Timelock.json');
const GovernorAlpha = require('../artifacts/contracts/GovernorAlpha.sol/GovernorAlpha.json');

chai.use(solidity)

async function governanceFixture(wallet, provider) {
  // deploy Pfx, sending the total supply to the deployer
  const timelockAddress = Contract.getContractAddress({ from: wallet.address, nonce: 1 })
  const pfx = await deployContract(wallet, Pfx, [wallet.address])

  // deploy timelock, controlled by what will be the governor
  const governorAlphaAddress = Contract.getContractAddress({ from: wallet.address, nonce: 2 })
  const timelock = await deployContract(wallet, Timelock, [governorAlphaAddress, TWO_DAYS])
  expect(timelock.address).to.be.eq(timelockAddress)

  // deploy governorAlpha
  const governorAlpha = await deployContract(wallet, GovernorAlpha, [timelock.address, pfx.address])
  expect(governorAlpha.address).to.be.eq(governorAlphaAddress)

  return { pfx, timelock, governorAlpha }
}

module.exports = {
  governanceFixture
}
