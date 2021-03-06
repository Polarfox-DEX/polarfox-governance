const HDWalletProvider = require('@truffle/hdwallet-provider')
const fs = require('fs')

const EIGHTEEN_ZEROS = '000000000000000000'

const CHAIN_ID = {
    AVALANCHE: 43114,
    FUJI: 43113
}

// Is production
const IS_PRODUCTION = false

const PROVIDER = {
    [CHAIN_ID.AVALANCHE]: 'https://api.avax.network/ext/bc/C/rpc',
    [CHAIN_ID.FUJI]: 'https://api.avax-test.network/ext/bc/C/rpc'
}

// Danger zone
const MNEMONIC = '../mnemonic'

// Utilities
function safeReadFile(path) {
    try {
        return fs.readFileSync(path, 'utf8').trim()
    } catch (error) {
        console.error('An error occurred in safeReadFile("' + path + '"):\n', error)
    }
}

function getProvider(chainId) {
    const devMnemonic = safeReadFile(MNEMONIC)
    console.log('Dev mnemonic OK:', devMnemonic != undefined)

    return new HDWalletProvider(devMnemonic, PROVIDER[chainId])
}

// Export
module.exports = {
    EIGHTEEN_ZEROS,
    CHAIN_ID,
    IS_PRODUCTION,
    getProvider
}
