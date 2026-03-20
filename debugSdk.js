
const { unmarshall } = require('@aws-sdk/util-dynamodb');
class TheorimClient {
    // Constructor
    constructor(event={}){
        this.input = event.input || {};
        this.api_url = "http://host.docker.internal:8080/api"; // internal docker localhost ref
        this.api_key = 'apikey';
        this.user = event.env?.user || '';
        this.#user_credentials = { ...(event.env?.user_credentials || {}) };
    }

    // --- Private Properties --- //
    #user_credentials;
    #ranPull = false;

    // --- Public Getters --- //
    get user_credentials() {
        if (!this.#ranPull) {
            throw new Error('Call await pullCredentials() before accessing user_credentials.');
        }
        return this.#user_credentials;
    }

    // --- Public Methods --- //
    async pullCredentials() {
        const promises = [];

        if (this.api_key) {
            promises.push(
                this.#getParameter(this.api_key).then(val => { this.api_key = val; }).catch(err => { this.api_key = null })
            );
        }

        for (const [name, path] of Object.entries(this.#user_credentials)) {
            if (path) {
                promises.push(
                    this.#getParameter(path).then(val => { this.#user_credentials[name] = val; }).catch(err => { this.#user_credentials[name] = null })
                );
            }
        }

        await Promise.all(promises);
        this.#ranPull = true;
    }
    
    validateInput(body={}, fields){
        if (typeof(fields) !== 'object' || !fields || Object.keys(fields).length == 0){ throw 'Invalid fields argument' }
        const invalidFields = [];
        for (const [fieldName, validator] of Object.entries(fields)){
            if (typeof(validator) === 'string'){
                if (typeof(body[fieldName]) !== validator){
                    invalidFields.push(fieldName);
                } 
            } else if (typeof(validator) === 'function') {
                const valid = validator(body[fieldName]);
                if (!valid){ invalidFields.push(fieldName) }
            }
        }
        return invalidFields.join(',');
    }

    response(status,message,output={}){
        if (typeof(status) != 'number'){ throw 'Invalid Status Argument' }
        if (typeof(message) !== 'string'){ throw 'Invalid return message' } 
        const returnObj = { output }
        if (status !== 200){ returnObj.error = message }
        else { returnObj.message = message }
        return { statusCode: status, body: JSON.stringify(returnObj) }
    }

    detectChanges(fields,event){
        if (!Array.isArray(fields)){ throw 'Invalid fields argument' }
        // { OLD_IMAGE, NEW_IMAGE, NEW_VALUES, OLD_VALUES }
        const results = [];
        for (const r of event.Records){
            const { eventName, dynamodb } = r;
            const changes = {
                OldImage: dynamodb.OldImage ? unmarshall(dynamodb.OldImage) : {},
                NewImage: dynamodb.NewImage ? unmarshall(dynamodb.NewImage) : {},
                Changes: {},
                eventName: eventName
            }
            for (const f of fields){
                if (changes.OldImage[f] !== changes.NewImage[f]){
                    changes.Changes[f] = {
                        NewValue: changes.NewImage[f],
                        OldValue: changes.OldImage[f]
                    };
                }
            }
            if (Object.keys(changes.Changes).length > 0){
                results.push(changes);
            }
        }
        return results;
    }

    async callTheorimApi(path, body = {}) {
        if (!this.#ranPull) {
            throw new Error('Call await pullCredentials() before making API calls.');
        }
        if (!this.api_key){
            throw new Error('API key not set. Ensure this action is assigned a service account. If this is a hook, THEORIM_API_URL and THEORIM_APP_ID must be set as env variables.');
        }
        if (!this.api_url){
            throw new Error('The THEORIM_API_URL lambda environment variable is not set. Set this directly in Lambda.');
        }
        const url = `${this.api_url.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;
        const hasBody = Object.keys(body).length > 0;
        const options = {
            method: hasBody ? 'POST' : 'GET',
            headers: {
                'x-api-key': this.api_key
            }
        };
        if (hasBody) {
            options.headers['Content-Type'] = 'application/json';
            options.body = JSON.stringify(body);
        }
        const res = await fetch(url, options);
        if (!res.ok) {
            const text = await res.text();
            throw new Error(`Theorim API ${res.status}: ${text}`);
        }
        return res.json();
    }

    // --- Private Helpers --- //
    async #getParameter(path) {
        const map ={
            'apikey': "theorim_BfIz0ZkWmI-aa6B-VEI_p96hSujbtwZ9-vlYSy5NZak"
        }
        return new Promise((resolve, reject) => {
            if (!path) {
                return reject(new Error('Parameter path is required'));
            }
            setTimeout(() => {
                resolve(map[path.split('/').pop()] || '');
            }, 100);
        });
    }
}

module.exports = TheorimClient;