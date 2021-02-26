import base64, json, os, praw, requests
from spotipy import util
import pandas as pd
import numpy as np
from google.cloud import pubsub_v1, storage, secretmanager

def reddit_obj():
    # Create a reddit object to make API calls with
    # call credentials from GCP Secret Manager. (from GcpMethods class below).
    secret = GcpMethods().get_secret()
    client_id, client_secret, user, application = secret['client_id'], secret['client_secret'], secret['user'], secret['application'] 
    user_agent = f"script:{application} (by u/{user}"
    reddit = praw.Reddit(
            client_id=client_id,
            client_secret=client_secret,
            user_agent=user_agent)
    return reddit

def spotify_auth(grant_type):
    # spotify credential jazz for their API
    # authorize token: prompts web page URI, used to update personal playlist
    # client token: API access for server, looking up URIs and the such
    secret = GcpMethods().get_secret()
    client_id, client_secret, user = secret['client_id'], secret['client_secret'], secret['user']

    # parameters in request for authorized access token
    redirect_uri = "https://localhost:8080"
    scope = "playlist-modify-public"
    # parameters for client token
    client_token_url = "https://accounts.spotify.com/api/token"
    bstr=bytes(f"{client_id}:{client_secret}", "utf-8")
    b64_auth = base64.b64encode(bstr)
    client_header = {"Authorization": f"Basic {b64_auth}"}
    client_body = {"grant_type": "client_credentials", "Content-Type": "application/x-www-form-urlencoded"}
    
    # token generation 
    if grant_type=="user":
        token = util.prompt_for_user_token(
            username=user, 
            scope=scope,
            client_id=client_id, 
            client_secret=client_secret, 
            redirect_uri=redirect_uri)
    elif grant_type=="client":
        res = requests.post(
            url=client_token_url,
            auth=(client_id, client_secret),
            data=client_body)
        token = res.json()['access_token']
    else:
        raise KeyError("need to select user or client authentication for spotify api")
    
    return token

class GcpMethods:
    def __init__(self):
        pass

    def read_gcs_json(self, bucket, blob):
        blob_obj = storage.Client().get_bucket(bucket).blob(blob)
        json_load = json.loads(blob_obj.download_as_string(client=None))
        return json_load

    def read_gcs_tsv(self, bucket, blob):
        # read a tsv / csv file from GCS. 
        # blob_obj = storage.Client().get_bucket(bucket).blob(blob)
        # write and load from temp storage
        # tmp_file = "/tmp/tmpfile.tsv"
        # blob.download_to_filename(tmp_file) 
        # with open(tmp_file) as f:
            # list_load = csv.DictReader(f, delimiter='\t')
        blob_obj = f"gs://{bucket}/{blob}"
        df = pd.read_csv(blob_obj, delimiter="\t")
        df = df.replace({np.nan: None})
        return df 

    def write_gcs(self, bucket, blob, blob_data):
        # write a file to GCS
        accepted_files = [".csv", ".json", ".tsv", ".txt"]
        if blob[blob.find("."):] not in accepted_files: 
            raise TypeError(f"gcs file needs to be in {accepted_files} type") 
        # start the storage client to write in blob from string
        storage_client = storage.Client()
        bucket = storage_client.get_bucket(bucket)
        blob = bucket.blob(blob)
        blob.upload_from_string(blob_data.to_csv(index=False, sep="\t"), 'text/csv')
        return 200

    def get_secret(self):
        # retrieve secrets for API access.
        # get client details from environment variables
        project_id, secret_id, version = os.environ['GCP_PROJECT_ID'], os.environ['EXTERNAL_APP_SECRET_NAME'], os.environ['EXTERNAL_APP_SECRET_VERSION'] 
        client = secretmanager.SecretManagerServiceClient()
        # call the client to retrieve secret
        name = f"projects/{project_id}/secrets/{secret_id}/versions/{version}"  # client.secret_version_path(project_id, secret_id, version)
        response = client.access_secret_version(request={'name': name})
        payload = response.payload.data.decode('UTF-8')
        # parse secret into dictionary
        payload_parsed = json.loads(payload)
        return payload_parsed 

    def pubsub_push(self, message):
        # given a dictionary (json), push the data to pubsub to be read by another function
        # get env vars and instantiate the client
        project_id, topic = os.environ['GCP_PROJECT_ID'], os.environ['PUBSUB_TOPIC']
        publisher = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(project_id, topic)
        # conver message to bytes to pass
        message_bytes = u'{}'.format(message).encode('utf-8')
        # Publishes a message
        try:
            publish_future = publisher.publish(topic_path, data=message_bytes)
            publish_future.result()  # Verify the publish succeeded
            return 200 
        except Exception as e:
            return (e, 500)

    def pubsub_read(self, event):
        # get the data from a pubsub message
        msg = json.loads(event.decode('utf-8'))
        msg = base64.b64decode(msg['data'])
        return msg 
