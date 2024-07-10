""" Import module needed to perform API call and send logs to Datadog"""
import logging
import os
import json
import requests
from requests.adapters import HTTPAdapter, Retry
from botocore.exceptions import ClientError
import boto3
from logger.logger import configure_logger

logger = logging.getLogger()

# Variables declaration used multiple times
api_endpoint = os.environ.get("CORE_API_ENDPOINT")

@configure_logger(level=os.environ.get("LOG_LEVEL", "INFO"))
def lambda_handler(event, context):
    """ Function used by AWS Lambda """
    secret_arn = os.environ.get("CORE_API_SECRET_ARN")
    region_name = "eu-west-3"

    # Get Secret value from SecretManager
    session = boto3.session.Session()
    secretsmanager_client = session.client(service_name='secretsmanager', region_name=region_name)
    try:
        secret_value_response = secretsmanager_client.get_secret_value(SecretId=secret_arn)
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            logger.error("The requested secret %s was not found", secret_arn)
        elif e.response['Error']['Code'] == 'InvalidRequestException':
            logger.error("The request was invalid due to: %s", e)
        elif e.response['Error']['Code'] == 'InvalidParameterException':
            logger.error("The request had invalid params: %s", e)
        elif e.response['Error']['Code'] == 'DecryptionFailure':
            logger.error("The requested secret can't be decrypted using the provided KMS key: %s", e)
        elif e.response['Error']['Code'] == 'InternalServiceError':
            logger.error("An error occurred on service side: %s", e)
    else:
        secret_string = json.loads(secret_value_response['SecretString'])
        api_key = secret_string['API_KEY']

    # Perform the POST API request
    requests_session = requests.Session()
    # Retry 5 times with ~1s between each retry
    # only if response code is 409
    retries = Retry(total=5,
                backoff_factor=1,
                status_forcelist=[ 409 ])
    try:
        requests_session.mount('https://', HTTPAdapter(max_retries=retries))
        headers = {
            "Authorization": f"apikey {api_key}"
        }
        response = requests_session.post(api_endpoint, headers=headers, timeout=10)
        if response.status_code == 200:
            logger.info("Response : %s", response.content)
        else:
            logger.error("Request error %s with code %s", response, response.status_code)
    except requests.exceptions.Timeout as err_timeout:
        logger.error("Request timeout. %s", err_timeout)
    except requests.exceptions.RequestException as err_request:
        logger.error("Request error. %s", err_request)

if __name__ == '__main__':
    api_key_local_run = os.environ.get("CORE_API_KEY")
    # Perform the POST API request
    retries_local_run = Retry(total=5,
                backoff_factor=1,
                status_forcelist=[ 409 ])
    requests_session_local_run = requests.Session()
    requests_session_local_run.mount('https://', HTTPAdapter(max_retries=retries_local_run))

    headers_local_run = {
            "Authorization": f"apikey {api_key_local_run}"
    }
    response_local_run = requests_session_local_run.post(api_endpoint, headers=headers_local_run, timeout=10)
    if response_local_run.status_code == '200':
        print("OK ",response_local_run.status_code)
    else:
        print("Request error ",response_local_run, "with code ", response_local_run.status_code)
