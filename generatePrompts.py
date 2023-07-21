from azure.servicebus import ServiceBusClient, ServiceBusMessage
import os

CONNECTION_STR = os.environ.get('SERVICE_BUS_CONN_STR')
QUEUE_NAME = "pendingPrompts"

def send_messages_to_queue():
    servicebus_client = ServiceBusClient.from_connection_string(conn_str=CONNECTION_STR, logging_enable=True)

    # Open and read the azure-services.txt file
    with open("azure-services.txt", "r") as f:
        services = f.readlines()

    with servicebus_client:
        sender = servicebus_client.get_queue_sender(queue_name=QUEUE_NAME)
        with sender:
            count = 0  # Counter to keep track of number of sent messages
            for service in services:
                if count >= 100:  # Break out if we've reached 100 messages
                    break
                service = service.strip()  # remove any leading/trailing whitespace or newline
                message = ServiceBusMessage(f"Write a 100-word love poem about {service}")
                sender.send_messages(message)
                print(f"Sent message {count+1} for {service}")
                count += 1

if __name__ == "__main__":
    send_messages_to_queue()
