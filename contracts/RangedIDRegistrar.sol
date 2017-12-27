pragma solidity ^0.4.15;
contract RangedIDRegistrar {
  // contract owner
  address public contrOwner = msg.sender;
  
  // Token mapping
  mapping (address => User) public user;
  struct User {
    // deposit & locked balance
    uint256 balance;
    uint256 lockedBalance;
    // for pre-order
    bytes32 hash;
    uint256 timestamp;
  }

  // ID mapping
  mapping(uint120 => Record) public record; // version: 4bit, TLDc: 16bit, cc: 4bit, SLDc: 40bit, prefixLen: 8bit, prefix: 48bit
  struct Record { // CC: b'1011, ID Prefix data
    address owner;
    uint64 timestamp;
  }

  // incr parameters
  uint16 public incrTLDc;
  uint40 public incrIndex;
  
  // pow param
  uint16  public powTLDc; // [0x1100, 0x11ff]
  uint32  public diff = 0x207fffff; // the PoW success pobablity = 1/2
  uint256 public tgt;

  // preOrder param
  uint16 public preTLDc; // [0x1200, 0x12ff]]

  // Events
  event NewOwner(uint120 key, address owner);
  event TransferRight(uint120 key, address owner);

  // constructor 
  function RangedIDRegistrar(){
    // incr parameter
    incrTLDc = 0x1000; // [0x1000, 0x10ff]
    incrIndex = 0;
    // pow parameter
    powTLDc = 0x11ff; // [0x1100, 0x11ff]
    diff = 0x207fffff; // the PoW success pobablity = 1/2    
    // calculate difficulty target
    uint256 coefficient = uint256(uint24(diff));
    uint256 exponent = uint256((diff >> 24));
    tgt = coefficient << (8 * (exponent - 3)); // 0x03a30c0000000000000000000000000000000000000000000000000000000000;
  }

  // deposit function
  function deposit() payable public returns(bool){
    if (msg.value > 0
	&& (user[msg.sender].balance + msg.value) > user[msg.sender].balance) {
      user[msg.sender].balance += msg.value;
      return true;
    }
    return false;
  }
  // pay token function 
  function payExcute(address _to, uint256 _money) public returns(bool){
    if (user[msg.sender].balance >= _money
        && _money > 0
        && (user[_to].balance + _money) > user[_to].balance) {
      user[msg.sender].balance -= _money;
      user[_to].balance += _money;      
      return true;
    }
    return false;
  }
  // withdraw eth
  function withdraw(uint256 _money) public returns(bool){
    if (_money <= user[msg.sender].balance
        && _money > 0) {
      if (true == msg.sender.send(_money)) {
	user[msg.sender].balance -= _money;
	return true;
      }
    }
    return false;
  }
  // check account's balance
  function getBalance(address _addr, uint8 _type) public returns(uint256){
    if (_type == 1) {
      return user[_addr].balance;
    } else if (_type == 2) {
      return user[_addr].lockedBalance;
    } else {
      return 0;
    }
  }  
  
  // updateDiffTarget
  function updDiffTgt(uint32 _diff) public returns(int){
    // The only contract owner can change the difficulty of PoW
    if (contrOwner != msg.sender) {
	return -101;
    }
    // calculate difficulty target
    uint256 coefficient = uint256(uint24(_diff));
    uint256 exponent = uint256((_diff >> 24));
    diff = _diff;
    tgt = coefficient << (8 * (exponent - 3)); // 0x03a30c0000000000000000000000000000000000000000000000000000000000
    return 1;
  }

  // increment reg
  function incrReg() public returns(int) {
    // keyHead: 0x010**b, keyEnd: [0x0000000000_00_000000000000, 0xffffffffff_00_000000000000]
    uint24 keyHead = ((uint24(0xffffff) & (uint24(incrTLDc)) << 4) + uint24(0xb));
    uint96 keyEnd  = (uint96(incrIndex) << 56); // prefix: 8bit, value: 48bit
    uint120 key = (uint120(keyHead) << 96) + uint120(keyEnd);

    // always succeeding in this function without the case of issuing all IDs
    if (incrIndex == 0 && incrTLDc == 0x1100) { return -201; }
    // check insufficient deposit
    if (user[msg.sender].balance < 0.01 ether) { return -202; }

    // update database
    user[msg.sender].balance       -= 0.01 ether;
    user[msg.sender].lockedBalance += 0.01 ether;
    record[key].owner      = msg.sender;
    record[key].timestamp  = uint64(block.timestamp); // current block time
    // increment index and TLDc
    if (incrIndex == 0xffffffffff) {
      incrIndex = 0;
      incrTLDc += 1;
    } else {
      incrIndex += 1;
    }
    NewOwner(key, msg.sender);
    return 2;
  }
  
  // powReg
  function powReg(uint64 _inputKey, uint64 _blockHeight, address _sender, uint64 _nonce) public returns(int){
    // version: 4bit, TLDc: 16bit, CC: 4bit
    uint8 version = uint8(_inputKey >> 60); 
    uint16 TLDc = uint16(_inputKey >> 44); 
    uint8 CC = uint8(_inputKey >> 40) - ((uint8(TLDc) & 0x0f) << 4); 
    // blockhash: 256bit, powHash: 256bit
    uint256 blockHash = uint256(block.blockhash(_blockHeight));
    uint256 powHash; // for PoW
    // key: 0x0_1200_b_0011002200_00_000000000000
    uint120 key = (uint120(_inputKey) << 56) + uint120(0x00000000000000);
    
    // version Error
    if (version != 0) { return -301; }
    // TLDc Error
    if (TLDc < 0x1000 || TLDc > powTLDc) { return -302; }
    // CC Error
    if (CC != 11) { return -303; }    
    // this ID Space isn't revoked
    if (record[key].timestamp != 0) { return -304; }
    // the block height is valid ? 
    if (blockHash == 0
	|| _blockHeight > block.number
	|| _blockHeight < (block.number - 257)) { return -305; }
    // check the hash value
    powHash = uint256(sha3(_inputKey, blockHash, _sender, _nonce));
    if (powHash > tgt) { return -306; }
    // check the sender 
    if (_sender != msg.sender) { return -307; }
    // check the deposit value
    if (user[msg.sender].balance < 0.01 ether) { return -308; }
    
    // Issuing ID Space, Giving Ownership to the sender
    user[msg.sender].balance       -= 0.01 ether;
    user[msg.sender].lockedBalance += 0.01 ether;
    record[key].owner      = msg.sender;
    record[key].timestamp  = uint64(block.timestamp);
    NewOwner(key, msg.sender);
    return 3;
  }

  // add 
  function preOrderReg1(bytes32 _hash) public returns(int){
    user[msg.sender].hash = _hash;
    user[msg.sender].timestamp = block.timestamp;
    return 1;
  }
  function preOrderReg2(uint64 _key, uint64 _nonce) public returns(int){
    uint8 version = uint8(_key >> 60); 
    uint16 TLDc = uint16(_key >> 44); 
    uint8 CC = uint8(_key >> 40) - ((uint8(TLDc) & 0x0f) << 4);
    bytes32 curHash = sha3(_key, _nonce);
    uint120 key = (uint120(_key) << 56) + uint120(0x00000000000000);
    // version Error
    if (version != 0) { return -3001; }
    // TLDc Error
    if (TLDc < 0x1200 || TLDc > preTLDc) { return -3002; }
    // CC Error
    if (CC != 11) { return -3003; }
    // this ID Space isn't revoked
    if (record[key].timestamp != 0) { return -3004; }
    // don't match hash value
    if (user[msg.sender].hash != curHash) { return -3005; }
    if (user[msg.sender].timestamp + 120 hours > block.timestamp) { return -3006; }
    // check the deposit value
    if (user[msg.sender].balance < 0.01 ether) { return -3007; }
    
    // Issuing ID Space, Giving Ownership to the sender
    user[msg.sender].balance       -= 0.01 ether;
    user[msg.sender].lockedBalance += 0.01 ether;
    record[key].owner      = msg.sender;
    record[key].timestamp  = uint64(block.timestamp);
    NewOwner(key, msg.sender);
    return 3000;
  }
    
    

  function setSLDTimestamp(uint64 _sldKey, uint64 _timestamp) public returns(int){
    uint120 _key = uint120(_sldKey) << 56;
    // check owner addr
    if (record[_key].owner != msg.sender) { return -401; }
    // if timestamp = 0, this ID Space was already revoked
    if (record[_key].timestamp == 0) { return -402; }
    // check timestamp's value
    if ((record[_key].timestamp >= _timestamp) || (uint64(block.timestamp) >= _timestamp)) { return -403; }

    // update database
    record[_key].timestamp = _timestamp;
    return 4;
  }

  function revokeSLD(uint64 _sldKey) public returns(int){
    uint120 _key = uint120(_sldKey) << 56;
    // check owner addr
    if (record[_key].owner != msg.sender) { return -501; }
    // check timestamp's value
    if (record[_key].timestamp == 0) { return -502; }
    // if block.timestamp <= record[_key].timestamp + 90 days, this ID Space can't be revoked
    if (block.timestamp <= record[_key].timestamp + 90 days) { return -503; }

    // update database
    record[_key].timestamp = 0;
    user[msg.sender].lockedBalance -= 0.01 ether;
    user[msg.sender].balance += 0.01 ether;
    return 5;
  }
 
  function setOwner(uint120 _key, uint64 _validTime, address _to, uint8 _v, bytes32 _r, bytes32 _s) public returns(int){
    // if this ID Sapce is root of SLD, check timestamp != 0,
    // if this ID Space is not root of SLD, check timestamp whether it was revoked
    if (uint56(_key) == 0) {
      if (record[_key].timestamp == 0) { return -601; }
    } else {
      if (record[_key].timestamp <= uint64(block.timestamp)) { return -602; }
    }
   
    // check owner
    if (record[_key].owner != msg.sender) { return -603; }
    // check block timestamp
    if (block.timestamp > _validTime) { return -604; }
    // verify receiver's sign
    if (ecrecover(bytes32(sha3(_key, _validTime)), _v, _r, _s) != _to) { return -605; }
    // check receiver's balance
    if (user[_to].balance < 0.01 ether) { return -606; }
    
    // update Database
    record[_key].owner = _to;
    user[msg.sender].lockedBalance -= 0.01 ether;
    user[msg.sender].balance += 0.01 ether;
    user[_to].balance -= 0.01 ether;
    user[_to].lockedBalance += 0.01 ether;
    return 6;
  }

  struct UpData {
    uint64 sldKey;
    uint8 preLen;
    uint48 preNum;
  }
  struct DownData {
    uint8 subPreLen;
    uint48 subPreNum;
    uint120 subKey;
  }
  // give sub ID Space's right
  function setSubspaceOwner(uint120 _key, uint64 _validTime, uint56 _prefix, uint64 _ttl, address _to,
			    uint8 _v, bytes32 _r, bytes32 _s) public returns(int){
    // declaration
    UpData memory upData;
    upData.sldKey = uint64(_key >> 56);
    upData.preLen = uint8(_key >> 48);
    upData.preNum = uint48(_key);

    DownData memory downData;
    downData.subPreLen = uint8(_prefix >> 48);
    downData.subPreNum = uint48(_prefix);
    downData.subKey = (uint120(upData.sldKey) << 56) + uint120(_prefix);
    
    //  check whether this tx is made by owner
    if (record[_key].owner != msg.sender) { return -701; }
    // if this ID Sapce is root of SLD, check timestamp != 0,
    // if this ID Space is not root of SLD, check timestamp whether it was revoked
    if (uint56(_key) == 0) {
      if (record[_key].timestamp == 0) { return -702; }
    } else {
      if (record[_key].timestamp <= uint64(block.timestamp)) { return -703; }
    }
    // check block timestamp
    if (uint64(block.timestamp) > _validTime) { return  -704; }
    // check _prefix's parameter
    // 1. prefix length
    if (downData.subPreLen <= upData.preLen || downData.subPreLen > 48) { return -705; }
    // 2. prefix Num
    if (downData.subPreNum >= 2^downData.subPreLen) { return -706; }
    // 3. prefix value check
    if ((downData.subPreNum >> uint48(downData.subPreLen - upData.preLen)) != upData.preNum) { return -707; }
    // cehck _ttl
    if (uint56(_key) == 0) {
      if ((record[_key].timestamp + 90 days) < _ttl) { return -708; }
    } else {
      if (record[_key].timestamp < _ttl) { return -709; }
    }
    // verify receiver's sign
    if (ecrecover(bytes32(sha3(_key, _validTime, _prefix, _ttl, _to)), _v, _r, _s) != _to) { return -710; }
    // check subKey's ID Space
    uint8 i;
    for (i = 1; i < downData.subPreLen; i++) {
      if (record[uint120(upData.sldKey) + (uint120(i) << 48) + uint120(downData.subPreNum >> uint48(downData.subPreLen - 1))].timestamp > uint64(block.timestamp)) { return -611; }
    }
    
    // update database
    record[downData.subKey].owner     = _to;
    record[downData.subKey].timestamp = _ttl;
    return 7;    
  }
  // check
  
  // check key's owner
  function getAddr(uint120 _key) public returns(address){
    // keyHead: 0x01***b, keyEnd: [0x0000000000_00_000000000000, 0xffffffffff_00_000000000000]
    return record[_key].owner;
  }
  // check owner's timestamp
  function getTimestamp(uint120 _key) public returns(address){
    // timestamp: e.g. 0x0011223344556677,
    // if this ID Space is not root of SLD, TTL(Time To Live)
    // if this ID Space is root of SLD, timestamp represents a time of getting this ID Space
    return record[_key].timestamp;
  }
}
