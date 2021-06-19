const Web3 = require('web3')

const { IS_PRODUCTION, CHAIN_ID, getProvider } = require('./const')
const { TEAM_TREASURY_MULTISIG_ADDR } = require('./governanceConstants')

const pfx = require('../artifacts/contracts/PFX.sol/Pfx.json')

const chainId = IS_PRODUCTION ? CHAIN_ID.AVALANCHE : CHAIN_ID.FUJI

const provider = getProvider(chainId)

const web3 = new Web3(provider)

const deployPfx = async () => {
    try {
        const accounts = await web3.eth.getAccounts()

        console.log('Attempting to deploy PFX from the account', accounts[0])

        const deployedToken = await new web3.eth.Contract(pfx.abi)
            .deploy({
                data: pfx.bytecode,
                arguments: [
                    // The account to give all the initial tokens to
                    TEAM_TREASURY_MULTISIG_ADDR[chainId]
                ]
            })
            .send({
                from: accounts[0]
            })

        console.log('Token deployed to', deployedToken.options.address)
    } catch (error) {
        console.error('An error occurred in deployPfx():\n', error)
    }
}

deployPfx()
