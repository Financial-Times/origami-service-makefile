"use strict";

const { exec } = require('child_process');
const fs = require('fs');

const service = process.env.SERVICE_SYSTEM_CODE;
const region = (process.env.REGION || 'LOCAL').toLowerCase();
const vaultPath = `secret/teams/origami/${service}/${region}`;
const envFile = '.env';

if (!service) {
    console.warn(
        'Could not load environment variables from Vault. Service name is undefined.',
        'Set the environment variable "SERVICE_SYSTEM_CODE" in your Makefile.'
    );
    process.exit(1);
}

// Update an existing .env file with environment variables from Vault.
exec(`vault read -format=json ${vaultPath}`, (err, stdout, stderr) => {
    const result = err ? null : JSON.parse(stdout);

    // Handle errors.
    if (err || !result.data) {
        console.warn(
            `Could not load environment variables from Vault (${vaultPath}).`,
            (stdout ? `\nstdout: ${stdout}` : ''),
            (stderr ? `\nstderr: ${stderr}` : '')
        );
        process.exit(1);
    }

    // Get secrets object.
    const existingComments = {};
    const existingSecrets = fs.readFileSync(envFile).toString().trim().split('\n').reduce((secretsObject, line, index) => {
        if (line.trim().indexOf('#') == 0) {
            // Line is a comment.
            existingComments[index] = line;
        } else {
            // Line is a secret (environment variable).
            const secretArr = (line.includes('=') ? line.split('=') : null);
            if (secretArr) {
                secretsObject[secretArr[0]] = secretArr[1];
            }
        }
        return secretsObject;
    }, {});
    const vaultSecrets = result.data;
    const secrets = Object.assign(existingSecrets, vaultSecrets)

    // Create string of secrets for .env.
    const keys = Object.keys(secrets);
    let envContent = '';
    for (let index = 0; index <= keys.length - 1; index++) {
        const comment = existingComments[index];
        if (comment) {
            envContent += `${comment}\n`;
        }
        const key = keys[index];
        envContent += `${key}=${secrets[key]}\n`;
    }

    // Write .env secrets.
    fs.writeFileSync(envFile, envContent);
    console.log(`Vault secrets for "${service}" have been written to ${envFile}`);
    // Warn of variables which are not in Vault.
    const vaultSecretKeys = Object.keys(vaultSecrets);
    const nonVaultSecretKeys = Object.keys(existingSecrets).filter((existingKey) => {
        return !vaultSecretKeys.includes(existingKey);
    });
    console.log(`The following environment variables are custom and not stored in Vault:\n${nonVaultSecretKeys}.`);
    process.exit(1);
});
