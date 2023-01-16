from eth_account.messages import encode_defunct
from web3 import Web3


async def sign():
    goerli_web3 = Web3(Web3.HTTPProvider('https://endpoints.omniatech.io/v1/eth/goerli/public'))
    msg = "0.98"
    hash = Web3.soliditySha3(['string'],[msg])
    message = encode_defunct(hash)
    singed_msg = goerli_web3.eth.account.sign_message(message, "private_key")
    signature = singed_msg.signature.hex()
    print(signature)
