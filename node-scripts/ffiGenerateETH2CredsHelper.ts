// 1) Call staking-deposit-cli/deposit.sh new-mnemonic
// 2) Output the json in this repo so it doesn't pollute the real frxETH stuff
// 3) Parse the generated json
// 4) Output as bytes32 / something abi.decode-able

// Other Scipts
// tsx ffiGenerateETH2CredsHelper.ts

declare var require: any;
import { logger } from './logger';
import Axios from 'axios';
import * as dotenv from 'dotenv';
const path = require('path');
require("dotenv").config({ path: __dirname + `/../.env` });
const fs = require("fs");
const util = require('util');
const fsExtra = require('fs-extra');

// Promisification
const exec = util.promisify(require('child_process').exec);
const readdir = util.promisify(fs.readdir);

// Example
// tsx ffiGenerateETH2CredsHelper.ts --withdrawal-address 0xc6a7176F8a20dFE2Ea3888547B6a3FE119187438 --num-validators 3 --offset 0
(async () => {
  logger.info('[Start] Validating MSIG validators to add data...');

  // Fetch and process the args
  const withdrawalAddressIndex = process.argv.indexOf('--withdrawal-address'); 
  const numValidatorsIndex = process.argv.indexOf('--num-validators'); 
  const offsetIndex = process.argv.indexOf('--offset'); 
  let withdrawalAddr, numValidators, offset; 
  withdrawalAddr = ((withdrawalAddressIndex > -1) ? process.argv[withdrawalAddressIndex + 1] : "0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF");
  numValidators = ((numValidatorsIndex > -1) ? process.argv[numValidatorsIndex + 1] : 3);
  offset = ((offsetIndex > -1) ? process.argv[offsetIndex + 1] : 0);


  console.log('Withdrawal Address:', `${withdrawalAddr}`); 
  console.log('Number of Validators:', `${numValidators}`); 
  console.log('Offset:', `${offset}`); 

  // Prep the command
  const val_key_parent_folder = `${__dirname}/test-validator-jsons`;
  const validator_key_folder = `${val_key_parent_folder}/validator_keys`;
  let stakingDepCliCommand = `bash deposit.sh \
  --language english \
  --non_interactive \
  existing-mnemonic \
  --folder ${val_key_parent_folder} \
  --mnemonic="${process.env.MNEMONIC}" \
  --mnemonic-password CRAPPYPASSWORD \
  --validator_start_index ${offset} \
  --num_validators ${numValidators} \
  --chain mainnet \
  --keystore_password KEYKEYPASS \
  --eth1_withdrawal_address ${withdrawalAddr}
  `.replace(/ +/g, ' ');

  // console.log(stakingDepCliCommand);

  console.log("Empty the validator key folder");
  fsExtra.emptyDirSync(validator_key_folder);

  console.log("Execute the staking deposit json generation");
  const stkDepCliPromise = exec(stakingDepCliCommand, {
    cwd: process.env.STAKING_DEPOSIT_CLI_PATH
  });
  const stkDepCliPromiseChild = stkDepCliPromise.child; 

  stkDepCliPromiseChild.stdout.on('data', function(data) {
    // console.log('stdout: ' + data);
  });
  stkDepCliPromiseChild.stderr.on('data', function(data) {
      console.log('stderr: ' + data);
  });
  stkDepCliPromiseChild.on('close', function(code) {
      // console.log('closing code: ' + code);
  });
  const { stdout, stderr } = await stkDepCliPromise;

  console.log("Find the deposit data json files");
  const fileNames = await readdir(validator_key_folder);
  const regex = new RegExp(/deposit_data-\d*.json/gmiu);
  const txtFiles = fileNames.filter(fname => regex.test(fname));
  console.log("txtFiles: ", txtFiles);

  console.log("Clean up the json files and make one single result");
  console.log("This will help with using Foundry's StdJson");
  let new_json: any[] = [];
  for (let i = 0; i < txtFiles.length; i++) {
    // Fetch the json
    let dd_json_content = await fsExtra.readJsonSync(`${validator_key_folder}/${txtFiles[i]}`);
    
    for (let j = 0; j < dd_json_content.length; j++) {
      const { amount, deposit_message_root, fork_version, network_name, deposit_cli_version, ...rest } = dd_json_content[j];
      new_json.push(rest);
    }
    
    console.log(new_json);
  }

  // Make all the combined creds into one file
  await fsExtra.writeJsonSync(`${validator_key_folder}/combined-creds.json`, new_json, {});

  logger.info('[End] Validated MSIG validators to add data');
})();