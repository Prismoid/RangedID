# coding:utf-8
from web3 import Web3, HTTPProvider, IPCProvider
from web3.contract import ConciseContract
import json
import sys
import time

web3 = Web3(HTTPProvider('http://localhost:8545'))
# web3 = Web3(IPCProvider())

def howToUse(result):
    print("--- how to use ---")
    print("1. increment: python3 InstrIssue.py 1")
    print("2. pow: python3 InstrIssue.py 2 \"target ID Space's key(64bit)\" \"password\"")
    sys.exit(result)

# creating contract object
f = open("../build/contracts/RangedIDRegistrar.json")
contract_json = json.load(f)
f.close()
addr = contract_json["networks"]["1"]["address"]
abi  = contract_json["abi"]
contract = web3.eth.contract(abi, addr)

# open account.dat
f = open("account.dat", "r")
defaultAccount = ""
for defaultAccount in f:
    defaultAccount.strip()
f.close()

if (len(sys.argv) < 2):
    howToUse(-1)
    
instr = sys.argv[1] # 1: increment issue, 2: pow issue 

if (instr == "1" and len(sys.argv) == 2):
    finFlag = 0
    try:  
        result = contract.call({'from': defaultAccount}).incrReg()
        if (result > 0):
            result = contract.transact({'from': defaultAccount, 'gas': 4500000}).incrReg()
            print("Sending Increment Tx")
            print("Tx Hash: " + result)
        else:
            print("This Tx will not be verified under this condition")
            howToUse(result)            
    except: 
        import traceback
        traceback.print_exc()
elif (instr == "2" and len(sys.argv) == 4):
    password = sys.argv[3]
    if (not (web3.personal.unlockAccount(defaultAccount, password, 1))):
        print("This password will fail to unlock, so this programm stops")
        howToUse(-2)
    try:
        # steady variable
        inputKey = int(sys.argv[2], 16)
        tgt      = contract.call({'from': defaultAccount}).tgt()
        print(hex(tgt))
        # not steady variable
        curBlockNum = web3.eth.blockNumber
        powBlock = web3.eth.getBlock((curBlockNum - 1 - 12)) # need 12 confirmations
        curHash  = powBlock.hash
        nonce    = 0
        # flag
        finFlag  = 0
        while (True):
            if (curBlockNum < web3.eth.blockNumber):
                curBlockNum = web3.eth.blockNumber
                powBlock = web3.eth.getBlock((curBlockNum - 1 - 12)) # need 12 confirmations
                curHash  = powBlock.hash
                print(curHash)
                nonce = 0
            for i in range(1000000):
                if (int(web3.soliditySha3(['uint64', 'bytes32', 'address', 'uint64'], [inputKey, curHash, defaultAccount, nonce]), 16) <= tgt):
                    finFlag = 1
                    print("hey")
                    print(tgt)
                    break
                nonce += 1
            if (finFlag == 1):
                break
        print("--- PoW success ---")
        print(web3.soliditySha3(['uint64', 'bytes32', 'address', 'uint64'], [inputKey, curHash, defaultAccount, nonce]))


        web3.personal.unlockAccount(defaultAccount, password, 300)
        result = contract.call({'from': defaultAccount}).powReg(inputKey, curBlockNum - 13, defaultAccount, nonce)
        if (result > 0):
            result = contract.transact({'from': defaultAccount}).powReg(inputKey, curBlockNum - 13, defaultAccount, nonce)
            print("Sending PoW Tx")
            print("Tx Hash: " + result)
        else:
            print("This Tx will not be verified under this condition")
            howToUse(result)
    except:
        import traceback
        traceback.print_exc()
else:
    howToUse(-3)
