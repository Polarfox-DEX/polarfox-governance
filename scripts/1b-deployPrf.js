const Web3 = require('web3')

const { IS_PRODUCTION, CHAIN_ID, getProvider } = require('./const')
const { PFX, PFX_ROUTER } = require('./governanceConstants')

const prf = require('../artifacts/contracts/pfx/PFXRewardsFactory.sol/PFXRewardsFactory.json')

const chainId = IS_PRODUCTION ? CHAIN_ID.AVALANCHE : CHAIN_ID.FUJI

const provider = getProvider(chainId)

const web3 = new Web3(provider)

const deployPrf = async () => {
    try {
        const accounts = await web3.eth.getAccounts()

        console.log('Attempting to deploy PRF from the account', accounts[0])

        const deployedPRF = await new web3.eth.Contract(prf.abi)
            .deploy({
                data: prf.bytecode,
                arguments: [
                    PFX[chainId], // PFX
                    PFX_ROUTER[chainId] // PFX router
                ]
            })
            .send({
                from: accounts[0]
            })

        console.log('PRF deployed to', deployedPRF.options.address)
    } catch (error) {
        console.error('An error occurred in deployPrf():\n', error)
    }
}

deployPrf()
