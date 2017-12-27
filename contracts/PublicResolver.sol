pragma solidity ^0.4.15;

import './AbstractRangedIDRagistrar.sol';

contract PublicResolver {
  // contract's owner
  address public contrOwner = msg.sender;
  
  // contract declaration
  RangedIDRegistrar ridr;

  // resolution protocol
  bytes4 constant SIMPLIFIED_HTTP_RESOLUTION_PROTOCOL = 0x7e2db75c;
  
  // ID mapping 
  mapping(uint120 => Record) public record;
  struct Record { // CC: b'1011, ID Prefix data
    string url;
  }

  // set Ranged ID Registrar contract address
  function setAddr(address _addrRangedIDReg) public returns(bool){
    if (contrOwner == msg.sender) {
      ridr = RangedIDRegistrar(_addrRangedIDReg);
      return true;
    }
    return false;
  }

  // true if contract implements requested interface
  function supportsInterface(bytes4 interfaceID) constant returns (bool) {
    return interfaceID == SIMPLIFIED_HTTP_RESOLUTION_PROTOCOL;
  }
  

  // setting URL
  function setURL(uint120 _key, string _url) public returns(int){
    // only ID Space's owner can set URL
    if (ridr.getAddr(_key) != msg.sender) { return -101; }

    // update database
    record[_key].url = _url;
    
    return 1;
  }
  
}
