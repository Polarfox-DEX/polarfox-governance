// test/PFX.js
// Load dependencies
const { expect } = require('chai');
//const { ethers } = require('hardhat');

// Start test block
describe('PFX', function () {
  before(async function () {
    this.PFX = await ethers.getContractFactory("Pfx");
  });

  beforeEach(async function () {
    this.pfx = await this.PFX.deploy("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
    await this.pfx.deployed();
  });

  // Test case
  it('checks total supply', async function () {
    // Test if the returned value is the same one
    // Note that we need to use strings to compare the 256 bit integers
    expect((await this.pfx.totalSupply()).toString()).to.equal('538000000000000000000000000');
  });
});