const Web3 = require('web3')

const { IS_PRODUCTION, CHAIN_ID, getProvider } = require('./const')
const { TREASURY_VESTER_1, TREASURY_VESTER_2, TREASURY_VESTER_3, TREASURY_VESTER_4, TEAM_TREASURY } = require('./governanceConstants')

const treasuryVester = require('../artifacts/contracts/TreasuryVester.sol/TreasuryVester.json')
const pairTreasuryVester = require('../artifacts/contracts/PairTreasuryVester.sol/PairTreasuryVester.json')

const chainId = IS_PRODUCTION ? CHAIN_ID.AVALANCHE : CHAIN_ID.FUJI

const provider = getProvider(chainId)

const web3 = new Web3(provider)

const claim = async () => {
    const treasuryVester1 = new web3.eth.Contract(pairTreasuryVester.abi, TREASURY_VESTER_1[chainId])
    const treasuryVester2 = new web3.eth.Contract(pairTreasuryVester.abi, TREASURY_VESTER_2[chainId])
    const treasuryVester3 = new web3.eth.Contract(pairTreasuryVester.abi, TREASURY_VESTER_3[chainId])
    const treasuryVester4 = new web3.eth.Contract(pairTreasuryVester.abi, TREASURY_VESTER_4[chainId])
    const teamTreasuryVester = new web3.eth.Contract(treasuryVester.abi, TEAM_TREASURY[chainId])

    try {
        const accounts = await web3.eth.getAccounts()

        console.log('Attempting to claim from the account', accounts[0])

        await claimTreasuryVester(accounts, treasuryVester1, 'treasury vester #1')
        await claimTreasuryVester(accounts, treasuryVester2, 'treasury vester #2')
        await claimTreasuryVester(accounts, treasuryVester3, 'treasury vester #3')
        await claimTreasuryVester(accounts, treasuryVester4, 'treasury vester #4')
        await claimTreasuryVester(accounts, teamTreasuryVester, 'team treasury')
    } catch (error) {
        console.error('An error occurred in claim():\n', error)
    }
}

claim()

async function claimTreasuryVester(accounts, ptv, label) {
    console.log(`Claiming ${label}...`)

    await ptv.methods.claim().send({
        from: accounts[0]
    })

    console.log(`Claimed ${label}!`)
}
