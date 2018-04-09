const { exec } = require('child_process');
const fs = require('fs');

const service = process.env.SERVICE_SYSTEM_CODE;
let region = (process.env.REGION || 'LOCAL').toLowerCase();
const vaultPath = `secret/teams/origami/${service}/${region}`;
const envFile = '.env';

if (!service) {
    console.warn(
        'Could not load enviroment variables from Vault. Service name is undefined.',
        'Set the enviroment variable "SERVICE_SYSTEM_CODE" in your Makefile.'
    );
    process.exit(1);
}

// Update an existing .env file with enviroment variables from Vault.
exec(`vault read -format=json ${vaultPath}`, (err, stdout, stderr) => {
    const result = err ? null : JSON.parse(stdout);

    // Handle errors.
    if (err || !result.data) {
        console.warn(
            `Could not load enviroment variables from Vault (${vaultPath}).`,
            (stdout ? `\nstdout: ${stdout}` : ''),
            (stderr ? `\nstderr: ${stderr}` : '')
        );
        process.exit(1);
    }

    // Get secrets object.
    const existingSecrets = fs.readFileSync(envFile).toString().trim().split('\n').reduce((secretsObject, secret) => {
        const secretArr = (secret.includes('=') ? secret.split('=') : null);
        if (secretArr) {
            secretsObject[secretArr[0]] = secretArr[1];
        }
        return secretsObject;
    }, {});
    const vaultSecrets = result.data;
    const secrets = Object.assign(existingSecrets, vaultSecrets)

    // Create string of secrets for .env.
    const keys = Object.keys(secrets);
    let envContent = '';
    for (index = keys.length - 1; index >= 0; index--) {
        const key = keys[keys.length - index - 1];
        envContent += `${key}=${secrets[key]}\n`;
    }

    // Write .env secrets.
    fs.write(envFile, envContent, (err) => {
        if (err) {
            throw err;
        }
        console.log(`Vault secrets for "${service}" have been written to .env`);
        process.exit(1);
    });
});
