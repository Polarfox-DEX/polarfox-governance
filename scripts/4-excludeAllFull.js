const Web3 = require('web3')

const { IS_PRODUCTION, CHAIN_ID, getProvider } = require('./const')
const {
    PFX,
    OWNER_ADDR,
    TEAM_TREASURY_MULTISIG_ADDR,
    LIQUIDITY_MINING_MULTISIG_ADDR,
    GOVERNANCE_TREASURY_MULTISIG_ADDR,
    AIRDROP_ADDR,
    TREASURY_VESTER_1,
    TREASURY_VESTER_2,
    TREASURY_VESTER_3,
    TREASURY_VESTER_4,
    TEAM_TREASURY,
    PFX_REWARDS_FACTORY_ADDR
} = require('./governanceConstants')

const pfxContract = require('../artifacts/contracts/pfx/PFX.sol/Pfx.json')

const chainId = IS_PRODUCTION ? CHAIN_ID.AVALANCHE : CHAIN_ID.FUJI

const provider = getProvider(chainId)

const web3 = new Web3(provider)

const toExclude = [
    OWNER_ADDR,
    TEAM_TREASURY_MULTISIG_ADDR[chainId],
    LIQUIDITY_MINING_MULTISIG_ADDR[chainId],
    GOVERNANCE_TREASURY_MULTISIG_ADDR[chainId],
    AIRDROP_ADDR[chainId],
    TREASURY_VESTER_1[chainId],
    TREASURY_VESTER_2[chainId],
    TREASURY_VESTER_3[chainId],
    TREASURY_VESTER_4[chainId],
    TEAM_TREASURY[chainId],
    PFX_REWARDS_FACTORY_ADDR[chainId]
]

const excludeAllFull = async () => {
    const pfx = new web3.eth.Contract(pfxContract.abi, PFX[chainId])

    try {
        const accounts = await web3.eth.getAccounts()

        console.log('Attempting to exclude all full from the account', accounts[0])

        toExclude.map(async (address) => await excludeFull(accounts, pfx, address))
    } catch (error) {
        console.error('An error occurred in excludeAllFull():\n', error)
    }
}

excludeAllFull()

async function excludeFull(accounts, pfx, address) {
    try {
        console.log('Excluding', address, 'in full')

        await pfx.methods
            .excludeSrc(
                address // The account to exclude from fees as source
            )
            .send({
                from: accounts[0]
            })

        console.log(`excludeSrc(${address}) OK`)

        await pfx.methods
            .excludeDst(
                address // The account to exclude from fees as recipient
            )
            .send({
                from: accounts[0]
            })

        console.log(`excludeDst(${address}) OK`)
    } catch (error) {
        console.log('An error occurred in excludeAirdropFull():', error)
    }
}
