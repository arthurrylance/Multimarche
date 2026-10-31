import solc from 'solc';
import {readFileSync,writeFileSync} from 'node:fs';
const input={language:'Solidity',sources:{'MultimarcheAudit.sol':{content:readFileSync('contracts/MultimarcheAudit.sol','utf8')}},settings:{optimizer:{enabled:true,runs:200},evmVersion:'paris',outputSelection:{'*':{'*':['abi','evm.bytecode.object']}}}};
const output=JSON.parse(solc.compile(JSON.stringify(input)));
for(const error of output.errors??[])if(error.severity==='error')throw new Error(error.formattedMessage);
const contract=output.contracts['MultimarcheAudit.sol'].MultimarcheAudit;
writeFileSync('src/audit-contract.json',JSON.stringify({compiler:solc.version(),abi:contract.abi,bytecode:'0x'+contract.evm.bytecode.object},null,2)+'\n');
console.log('Compiled Sepolia audit contract.');
