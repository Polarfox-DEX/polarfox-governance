const chai = require('chai');
const { expect } = chai;

const { constants } = require('ethers');
const { solidity, MockProvider, createFixtureLoader } = require('ethereum-waffle');

const { governanceFixture } = require('./fixtures');

const { TWO_DAYS, THREE_DAYS } = require('./utils');

chai.use(solidity)

describe('GovernorAlpha', () => {
  const provider = new MockProvider({
    ganacheOptions: {
      hardfork: 'istanbul',
      mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
      gasLimit: 9999999,
    },
  })
  const [wallet] = provider.getWallets()
  const loadFixture = createFixtureLoader(wallet, provider)

  let pfx
  let timelock
  let governorAlpha

  beforeEach(async () => {
    const fixture = await loadFixture(governanceFixture)
    // console.log('fixture', fixture)
    pfx = fixture.pfx
    timelock = fixture.timelock
    governorAlpha = fixture.governorAlpha
  })

  it('pfx', async () => {
    const balance = await pfx.balanceOf(wallet.address)
    const totalSupply = await pfx.totalSupply()
    expect(balance).to.be.eq(totalSupply)
  })

  it('timelock', async () => {
    const admin = await timelock.admin()
    expect(admin).to.be.eq(governorAlpha.address)
    const pendingAdmin = await timelock.pendingAdmin()
    expect(pendingAdmin).to.be.eq(constants.AddressZero)
    const delay = await timelock.delay()
    expect(delay).to.be.eq(TWO_DAYS)
  })

  it('governor', async () => {
    const votingPeriod = await governorAlpha.votingPeriod()
    expect(votingPeriod).to.be.eq(THREE_DAYS)
    const timelockAddress = await governorAlpha.timelock()
    expect(timelockAddress).to.be.eq(timelock.address)
    const pfxFromGovernor = await governorAlpha.pfx()
    expect(pfxFromGovernor).to.be.eq(pfx.address)
  })
});
