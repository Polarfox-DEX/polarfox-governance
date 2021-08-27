const Web3 = require('web3')

const { IS_PRODUCTION, CHAIN_ID, getProvider } = require('./const')
const { PFX_REWARDS_FACTORY_ADDR, PRF_RATIOS, PRF_POOLS, PRF_STAKING_REWARDS } = require('./governanceConstants')

const prfContract = require('../artifacts/contracts/pfx/PFXRewardsFactory.sol/PFXRewardsFactory.json')

const chainId = IS_PRODUCTION ? CHAIN_ID.AVALANCHE : CHAIN_ID.FUJI

const provider = getProvider(chainId)

const web3 = new Web3(provider)

const setPfxPools = async () => {
    const accounts = await web3.eth.getAccounts()
    const prf = new web3.eth.Contract(prfContract.abi, PFX_REWARDS_FACTORY_ADDR[chainId])

    try {
        console.log(`Setting the PFX pools on PRF...`)

        await prf.methods
            .setPfxPools(
                PRF_RATIOS[chainId],
                PRF_POOLS[chainId],
                PRF_STAKING_REWARDS[chainId]
            )
            .send({
                from: accounts[0]
            })

        console.log(`Successfully set the PFX pools on PRF!`)
    } catch (error) {
        console.log('An error occurred in setPfxPools():', error)
    }
}

setPfxPools()
