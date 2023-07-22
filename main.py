import os
import sys
import asyncio
from datetime import datetime, timedelta

import openai
from openai.error import RateLimitError
from azure.servicebus.aio import ServiceBusClient
from azure.servicebus import ServiceBusMessage


# Constants
CONNECTION_STR = os.getenv('SERVICE_BUS_CONN_STR')
INCOMING_QUEUE_NAME = "pendingPrompts"
OUTGOING_QUEUE_NAME = "generatedPrompts"
TOKENS_PER_SECOND_THRESHOLD = float(os.getenv('TARGET_TPM', '10')) * 1000 / 60 # 10K TPM by default
DELAY_SECONDS = 10
TOKEN_WINDOW_EXPIRATION_SECONDS = 60
RETRY_COUNT = 3

# Concurrency
CONCURRENCY_LIMIT = 10

def configure_openai():
    """Set up the OpenAI configuration."""
    openai.api_type = "azure"
    openai.api_base = os.getenv("AZURE_OPENAI_ENDPOINT")
    openai.api_version = "2023-05-15"
    openai.api_key = os.getenv("AZURE_OPENAI_KEY")

def check_connection_string():
    """Ensure the connection string environment variable is set."""
    if not CONNECTION_STR:
        print("Error: The environment variable SERVICE_BUS_CONN_STR is not set or is empty.")
        sys.exit(1)


async def process_with_openai(prompt):
    """Process the prompt with OpenAI and return the response and token count."""
    loop = asyncio.get_running_loop()
    retries = RETRY_COUNT
    
    while retries > 0:
        try:
            response = await loop.run_in_executor(None, lambda: openai.ChatCompletion.create(
                engine="gpt-35-turbo-v0301",
                messages=[
                    {"role": "user", "content": prompt}
                ]
            ))
            return response["choices"][0]["message"]["content"], response["usage"]["total_tokens"]
        
        except RateLimitError as e:
            retries -= 1
            global TOKENS_PER_SECOND_THRESHOLD
            TOKENS_PER_SECOND_THRESHOLD *= 0.7
            print(f"Warning: {str(e)}. Reducing token threshold by 30% and waiting 10 seconds before retrying.")
            await asyncio.sleep(10)

    raise Exception(f"Failed to process prompt with OpenAI after {RETRY_COUNT} retries.")

async def should_throttle(tokens):
    """Determine if processing should be throttled based on token consumption."""
    global token_window

    now = datetime.utcnow()
    token_window.append((now, tokens))

    def calculate_tokens_per_second():
        if not token_window:
            return 0
        elapsed_seconds = (datetime.utcnow() - token_window[0][0]).seconds + 1
        return sum(token_count for _, token_count in token_window) / elapsed_seconds

    tokens_per_second = calculate_tokens_per_second()
    tokens_per_thousand_minute = tokens_per_second * 60 / 1000
    threshold_per_thousand_minute = TOKENS_PER_SECOND_THRESHOLD * 60 / 1000

    print(f"Current: {tokens_per_thousand_minute:.2f}K TPM / Target: {threshold_per_thousand_minute:.2f}K TPM")


    cutoff = datetime.utcnow() - timedelta(seconds=TOKEN_WINDOW_EXPIRATION_SECONDS)
    token_window = [(t, token_count) for t, token_count in token_window if t > cutoff]

    return tokens_per_second > TOKENS_PER_SECOND_THRESHOLD

async def process_single_message(msg, sender, semaphore):
    """Process a single message."""
    global TOKENS_PER_SECOND_THRESHOLD
    async with semaphore:
        
        prompt = str(msg)
        
        try:
            response_content, tokens = await process_with_openai(prompt)
        except RateLimitError:
            print("Warning: RateLimitError encountered!")
            TOKENS_PER_SECOND_THRESHOLD *= 0.5  # Reduce the threshold by 50%
            print(f"New TOKENS_PER_SECOND_THRESHOLD: {TOKENS_PER_SECOND_THRESHOLD}")
            return 
        
        while await should_throttle(tokens):
            print(f"Throttling due to token consumption. Sleeping for {DELAY_SECONDS} seconds...")
            await asyncio.sleep(DELAY_SECONDS)

        await sender.send_messages(ServiceBusMessage(response_content))
        await msg.complete()

async def process_queue_messages():
    """Process messages from the Azure Service Bus."""
    global token_window
    token_window = []

    semaphore = asyncio.Semaphore(CONCURRENCY_LIMIT)

    print("Attempting to connect to Azure Service Bus...")
    async with ServiceBusClient.from_connection_string(conn_str=CONNECTION_STR) as servicebus_client:
        async with servicebus_client.get_queue_receiver(queue_name=INCOMING_QUEUE_NAME, max_wait_time=5, message_visibility_timeout=600) as receiver, \
                   servicebus_client.get_queue_sender(queue_name=OUTGOING_QUEUE_NAME) as sender:
            print(f"Listening for messages from queue '{INCOMING_QUEUE_NAME}'...")

            tasks = []

            while True:
                msgs = await receiver.receive_messages(max_message_count=10) 
                if not msgs:
                    print("All messages processed. Sleeping for 30 seconds...")
                    await asyncio.sleep(30)
                
                for msg in msgs:
                    tasks.append(asyncio.create_task(process_single_message(msg, sender, semaphore)))

if __name__ == "__main__":
    configure_openai()
    check_connection_string()
    asyncio.run(process_queue_messages())
