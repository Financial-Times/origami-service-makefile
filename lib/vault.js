"use strict";

const { exec } = require('child_process');
const fs = require('fs');

const service = process.env.SERVICE_SYSTEM_CODE;
const region = (process.env.REGION || 'LOCAL').toLowerCase();
const vaultPath = `secret/teams/origami/${service}/${region}`;
const envFile = '.env';

if (!service) {
    throw new Error(`Could not load environment variables from Vault without a service code.
    Set the environment variable "SERVICE_SYSTEM_CODE" in your Makefile.`);
}

// Update an existing .env file with environment variables from Vault.
exec(`vault read -format=json ${vaultPath}`, (err, stdout, stderr) => {
    const result = err ? null : JSON.parse(stdout);

    // Handle errors.
    if (err || !result.data) {
        throw new Error(`
            Could not load environment variables from Vault (${vaultPath}).
            ${stdout ? `\nstdout: ${stdout}` : ''}
            ${stderr ? `\nstdout: ${stderr}` : ''}
            `
        );
    }


    // Get existings secrets and comments from the .env file.
    let existingComments = {};
    let existingSecrets = {};
    if (fs.existsSync(envFile)) {
        existingSecrets = fs.readFileSync(envFile).toString().trim().split('\n').reduce((secretsObject, line, index) => {
            if (line.startsWith('#')) {
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
    }

    // Get secrets from Vault.
    const vaultSecrets = result.data;
    const vaultSecretKeys = Object.keys(vaultSecrets);

    // Check local secrets which will be replaced with Vault vaules for inline comments.
    const replacedSecretKeys = Object.keys(existingSecrets).filter((existingKey) => {
        return vaultSecretKeys.includes(existingKey);
    });
    replacedSecretKeys.forEach((replacedSecretKey) => {
        const replacedSecret = existingSecrets[replacedSecretKey];
        const inlineComments = /^\s*(?:"(?:.*?)"|'(?:.*?)'|(?:[^\s#]*))?\s*(#.*)/mg;
        if (inlineComments.exec(replacedSecret)) {
            throw new Error(`The "${replacedSecretKey}" enviroment variable has an inline comment. Please move this comment to its own line.`);
        }
    });

    // Combine secrets and create string of secrets for .env.
    const secrets = Object.assign({}, existingSecrets, vaultSecrets)
    const secrentKeys = Object.keys(secrets);
    const envLineLength = secrentKeys.length + Object.keys(existingComments).length;
    let envContent = '';
    let numberofComments = 0;
    for (let index = 0; index <= envLineLength - 1; index++) {
        const comment = existingComments[index];
        if (comment) {
            numberofComments++;
            envContent += `${comment}\n`;
        } else {
            const key = secrentKeys[index - numberofComments];
            envContent += `${key}=${secrets[key]}\n`;
        }
    }

    // Write .env secrets.
    if (secrentKeys.length > 0) {
        fs.writeFileSync(envFile, envContent);
        console.log(`Vault secrets for "${service}" have been written to ${envFile}.`);
    } else {
        console.log(`No secrets to write to ${envFile}.`);
    }

    // Warn of variables which are not in Vault.
    const nonVaultSecretKeys = Object.keys(existingSecrets).filter((existingKey) => {
        return !vaultSecretKeys.includes(existingKey);
    });
    if (nonVaultSecretKeys.length > 0) {
        console.log(`The following environment variables are custom and not stored in Vault:\n${nonVaultSecretKeys}.`);
    }

    process.exitCode = 0;
});
