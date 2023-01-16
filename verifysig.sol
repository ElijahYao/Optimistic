// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;


/*
正常签名步骤
1. sing 签名
2. hash(message) 消息 hash
3. sign(hash(message), priveate key) 消息和私钥签名（链下完成）
4. ecrecover(ethHash(message), signature) == signer 恢复签名   参数1：hash后的消息原文， 参数2：链下签名
*/


// 签名验证合约, 签名\校验\恢复
contract Verifysig {
    // 校验签名是否正确
    // 参数1：签名人的地址
    // 参数2：消息原文
    // 参数3：签名结果
    function verify(address _signer, string memory _message, bytes memory _sign) external pure returns(bool){
        bytes32 messageHash = getMessageHash(_message);  // 消息 hash
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash); // 进行结果eth hash
        return recover(ethSignedMessageHash, _sign) == _signer;  // 恢复地址，进行比对
    }

    function getMessageHash(string memory _message) public pure returns(bytes32){
        return keccak256(abi.encodePacked(_message));
    }

    function getEthSignedMessageHash(bytes32 _messageHash) public pure returns(bytes32){
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32" , _messageHash));
    }

    function recover(bytes32 _ethSignedMessageHash, bytes memory _sign) public pure returns(address){
        // 非对称加密，开始解密
        (bytes32 r, bytes32 s, uint8 v) = _split(_sign);
        // 内部函数 ecrecover
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    // 通过切割拿到
    function _split(bytes memory _sign) public pure returns (bytes32 r, bytes32 s, uint8 v){
        require(_sign.length == 65, "invalid signature length");
        // 只能通过内联汇编进行分割， 前32位，中间32位，最后1位
        assembly {
            r := mload(add(_sign, 32))
            s := mload(add(_sign, 64))
            v := byte(0, mload(add(_sign, 96)))
        }
    }
}
