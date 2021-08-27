const Web3 = require('web3')

const { IS_PRODUCTION, CHAIN_ID, getProvider } = require('./const')
const { PFX, PFX_REWARDS_FACTORY_ADDR } = require('./governanceConstants')

const pfxContract = require('../artifacts/contracts/pfx/PFX.sol/Pfx.json')

const chainId = IS_PRODUCTION ? CHAIN_ID.AVALANCHE : CHAIN_ID.FUJI

const provider = getProvider(chainId)

const web3 = new Web3(provider)

const setReflectionAddress = async () => {
    const accounts = await web3.eth.getAccounts()
    const pfx = new web3.eth.Contract(pfxContract.abi, PFX[chainId])

    try {
        console.log(`Setting the reflection address on PFX to ${PFX_REWARDS_FACTORY_ADDR[chainId]}...`)

        await pfx.methods
            .setReflectionAddress(
                PFX_REWARDS_FACTORY_ADDR[chainId] // The new reflection address
            )
            .send({
                from: accounts[0]
            })

        console.log(`Successfully set the reflection address on PFX to ${PFX_REWARDS_FACTORY_ADDR[chainId]}!`)
    } catch (error) {
        console.log('An error occurred in setReflectionAddress():', error)
    }
}

setReflectionAddress()
