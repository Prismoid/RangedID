pragma solidity ^0.4.15;
contract RangedIDRegistrar {
  // contract owner
  address public contrOwner = msg.sender;
  
  // Token & Pre-Order Hash mapping
  mapping (address => User) public user;
  struct User {
    // deposit & locked balance
    uint256 balance;
    uint256 lockedBalance;
    // for pre-order
    bytes32 hash;
    uint64 blockHeight;
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

  // pre-order param
  uint16 public preTLDc; // [0x1100, 0x11ff]
  uint64 public preOrderN; // n = 100

  // Events
  event NewOwner(uint120 key, address owner);

  // constructor 
  function RangedIDRegistrar(){
    // incr parameter
    incrTLDc = 0x1000; // [0x1000, 0x10ff]
    incrIndex = 0;
    preTLDc  = 0x1100;
    preOrderN = 3;
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

  // increment reg
  function incrReg() public returns(bool) {
    // keyHead: 0x010**b, keyEnd: [0x0000000000_00_000000000000, 0xffffffffff_00_000000000000]
    uint24 keyHead = ((uint24(0xffffff) & (uint24(incrTLDc)) << 4) + uint24(0xb));
    uint96 keyEnd  = (uint96(incrIndex) << 56); // prefix: 8bit, value: 48bit
    uint120 key = (uint120(keyHead) << 96) + uint120(keyEnd);

    if (!(incrIndex == 0 && incrTLDc == 0x1100) // always succeeding in this function without the case of issuing all IDs
	&& !(user[msg.sender].balance < 0.01 ether)) { // check insufficient deposit
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
      return true;
    }
    return false;
  }

  // pre-order
  function preOrderReg1(bytes32 _hash) public returns(bool){
    user[msg.sender].hash = _hash;
    user[msg.sender].blockHeight = uint64(block.number);
    return true;
  }
  function preOrderReg2(uint64 _key, uint64 _nonce) public returns(bool){
    uint8 version = uint8(_key >> 60); 
    uint16 TLDc = uint16(_key >> 44); 
    uint8 CC = uint8(_key >> 40) - ((uint8(TLDc) & 0x0f) << 4);
    uint40 SLDc = uint40(_key);
    bytes32 curHash = sha3(_key, _nonce);
    uint120 key = (uint120(_key) << 56) + uint120(0x00000000000000);

    if (!(version != 0)     // version Error
	&& ((TLDc >= 0x1000 && TLDc < 0x1200))     // TLDc Error
	&& !(CC != 11)     // CC Error
	&& !(record[key].timestamp != 0)     // this ID Space isn't revoked
	&& !(user[msg.sender].hash != curHash)     // don't match hash value
	&& !(user[msg.sender].blockHeight + preOrderN  > block.number)     // check the block height
	&& !(user[msg.sender].balance < 0.01 ether)) {    // check the deposit value
      if (TLDc < 0x1100) {
	if (TLDc > incrTLDc) { return false; }
	if ((TLDc == incrTLDc) && (SLDc >= incrIndex)) { return false; }
      }
	
      // Issuing ID Space, Giving Ownership to the sender
      user[msg.sender].balance       -= 0.01 ether;
      user[msg.sender].lockedBalance += 0.01 ether;
      record[key].owner      = msg.sender;
      record[key].timestamp  = uint64(block.timestamp);
      NewOwner(key, msg.sender);
      return true;
    }
    return false;
  }    

  // timestamp update 
  function setSLDTimestamp(uint64 _sldKey, uint64 _timestamp) public returns(bool){
    uint120 _key = uint120(_sldKey) << 56;
    if (!(record[_key].owner != msg.sender)     // check owner addr
	&& !(record[_key].timestamp == 0)     // if timestamp = 0, this ID Space was already revoked
	&& !(record[_key].timestamp >= _timestamp) || (uint64(block.timestamp) >= _timestamp)) {     // check timestamp's value}
      // update database
      record[_key].timestamp = _timestamp;
      return true;
    }
    return false;
  }

  function revokeSLD(uint64 _sldKey) public returns(bool){
    uint120 _key = uint120(_sldKey) << 56;
    if (!(record[_key].owner != msg.sender)     // check owner addr
	&& !(record[_key].timestamp == 0)    // check timestamp's value
	&& !(block.timestamp <= record[_key].timestamp + 90 days)) {     // if block.timestamp <= record[_key].timestamp + 90 days, this ID Space can't be revoked
      // update database
      record[_key].timestamp = 0;
      user[msg.sender].lockedBalance -= 0.01 ether;
      user[msg.sender].balance += 0.01 ether;
      return true;
    }
    return false;
  }
 
  function setOwner(uint120 _key, uint64 _validTime, address _to, uint8 _v, bytes32 _r, bytes32 _s) public returns(bool){
    if (!(uint56(_key) == 0 && (record[_key].timestamp == 0))     // if this ID Sapce is root of SLD, check timestamp != 0,
	&& !(uint56(_key) != 0 && (record[_key].timestamp <= uint64(block.timestamp)))     // if this ID Space is not root of SLD, check timestamp whether it was revoked
	&& !(record[_key].owner != msg.sender)     // check owner
	&& !(block.timestamp > _validTime)     // check block timestamp
	&& !(ecrecover(sha3(_key, _validTime), _v, _r, _s) != _to)     // verify receiver's sign
	&& !(user[_to].balance < 0.01 ether)) {     // check receiver's balance
      // update Database
      record[_key].owner = _to;
      user[msg.sender].lockedBalance -= 0.01 ether;
      user[msg.sender].balance += 0.01 ether;
      user[_to].balance -= 0.01 ether;
      user[_to].lockedBalance += 0.01 ether;
      NewOwner(_key, _to);
      return true;
    }
    return false;
  }


  // give sub ID Space's right
  function setSubspaceOwner(uint120 _key, uint64 _validTime, uint56 _prefix, uint64 _ttl, address _to,
			    uint8 _v, bytes32 _r, bytes32 _s) public returns(int){
    // declaration
    /*
    if (!(record[_key].owner != msg.sender)     //  check whether this tx is made by owner
	&& !(uint56(_key) == 0 && (record[_key].timestamp == 0))     // if this ID Sapce is root of SLD, check timestamp != 0,
	&& !(uint56(_key) != 0 && (record[_key].timestamp <= uint64(block.timestamp)))     // if this ID Space is not root of SLD, check timestamp whether it was revoked
	&& !(uint64(block.timestamp) > _validTime)     // check block timestamp
	&& !(uint8(_prefix >> 48) <= uint8(_key >> 48) || uint8(_prefix >> 48) > 48)    // 1. prefix length
	&& !(uint48(_prefix) >= 2**uint8(_prefix >> 48))    // 2. prefix Num
	&& !((uint48(_prefix) >> uint48(uint8(_prefix >> 48) - uint8(_key >> 48))) != uint48(_key))    // 3. prefix value check
	&& !(uint56(_key) == 0 && (record[_key].timestamp + 90 days) < _ttl)    // cehck _ttl(root of SLD)
	&& !(uint56(_key) != 0 && (record[_key].timestamp < _ttl)) // check_ttl(not root of SLD)
	&& !(ecrecover(bytes32(sha3(_key, _validTime, _prefix, _ttl)), _v, _r, _s) != _to)) {     // verify receiver's sign
    */
    if ((record[_key].owner != msg.sender)) { return -101; }     //  check whether this tx is made by owner
    if ((uint56(_key) == 0 && (record[_key].timestamp == 0))) { return -102; }     // if this ID Sapce is root of SLD, check timestamp != 0,
    if ((uint56(_key) != 0 && (record[_key].timestamp <= uint64(block.timestamp)))) { return - 103; }     // if this ID Space is not root of SLD, check timestamp whether it was revoked
    if ((uint64(block.timestamp) > _validTime)) { return - 104; }     // check block timestamp
    if ((uint8(_prefix >> 48) <= uint8(_key >> 48) || uint8(_prefix >> 48) > 48)) { return -105; }    // 1. prefix length
    if ((uint48(_prefix) >= 2**uint8(_prefix >> 48))) { return - uint8(_prefix >> 48) * 5 - 1000; }    // 2. prefix Num
    if (((uint48(_prefix) >> uint48(uint8(_prefix >> 48) - uint8(_key >> 48))) != uint48(_key))) { return - uint48(_prefix) * 5 - 10000; }    // 3. prefix value check
    if ((uint56(_key) == 0 && (record[_key].timestamp + 90 days) < _ttl)) { return -108; }    // cehck _ttl(root of SLD)
    if ((uint56(_key) != 0 && (record[_key].timestamp < _ttl))) { return -109; } // check_ttl(not root of SLD)
    if ((ecrecover(bytes32(sha3(_key, _validTime, _prefix, _ttl)), _v, _r, _s) != _to)) { return -110; }      // verify receiver's sign
    uint8 i;
    for (i = 1; i < uint8(_prefix >> 48); i++) {
      if (record[uint120(uint64(_key >> 56)) << 64 + (uint120(i) << 48) + uint120(uint48(_prefix) >> uint48(uint8(_prefix >> 48) - 1))].timestamp > uint64(block.timestamp)) {
	return - int8(i);
      }
    }
    // update database
    record[(uint120(uint64(_key >> 56)) << 56) + uint120(_prefix)].owner     = _to;
    record[(uint120(uint64(_key >> 56)) << 56) + uint120(_prefix)].timestamp = _ttl;
    NewOwner((uint120(uint64(_key >> 56)) << 56) + uint120(_prefix), _to);
    return 1;
  }
  
  // check key's owner
  function getAddr(uint120 _key) public returns(address){
    // keyHead: 0x01***b, keyEnd: [0x0000000000_00_000000000000, 0xffffffffff_00_000000000000]
    return record[_key].owner;
  }
  // check owner's timestamp
  function getTimestamp(uint120 _key) public returns(uint64){
    // timestamp: e.g. 0x0011223344556677,
    // if this ID Space is not root of SLD, TTL(Time To Live)
    // if this ID Space is root of SLD, timestamp represents a time of getting this ID Space
    return record[_key].timestamp;
  }
  function getPreOrderHash(address _key) public returns(uint256){
    return uint256(user[_key].hash);
  }
  function getPreOrderBlockHeight(address _key) public returns(uint64){
    return user[_key].blockHeight;
  }
}
