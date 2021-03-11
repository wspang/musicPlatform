from reddit_ingest import Reddit
from spotify_ingest import Spotify 
from api_methods import GcpMethods, format_hive_partition
import pandas as pd
import json
import os

def config_handler(event, context):
    # called from scheduler. reads config from GCS to pass to reddit handler. Returns dictionary
    # triggered by pubsub, message doesnt matter though
    code_bucket = os.environ['CODE_BUCKET']
    blob_path = os.environ['CONFIG_FILE_PATH']
    config_json = GcpMethods().read_gcs_json(bucket=code_bucket, blob=blob_path)
    # spawn cloud function per subreddit.
    # flatten the config to make json per iter in playlist dict. then attach top level attribs.
    # convert to json string. write config to pubsub to pass to next function
    subs = config_json.pop('playlists')
    for payload in subs:
        payload.update(config_json)
        js_payload = json.dumps(payload)
        GcpMethods().pubsub_push(message=js_payload)
    return 200 

def reddit_handler(event, context):
    # Given reddit / playlist config, read reddit and parse for data. Export to GCS
    # triggered by pubsub topic. read message for config data
    payload = GcpMethods().pubsub_read(event=event)
    payload = json.loads(payload)
    post_count = payload['post_count']

    # set reddit and spotify (auth) objects
    redd = Reddit()

    # return list of records to export
    post_output = []

    # parse out the subreddit and spotify playlist to look up 
    sub = payload['sub']

    # get reddit posts for the sub
    posts = redd.get_posts(subreddit_name=sub, post_count=post_count)

    # parse post titles for track and artist
    #posts = [post.update(redd.parse_title(post['title'])) for post in posts]
    for post in posts:
        post.update(redd.parse_title(title=post['title']))

    # convert to df
    post_df = pd.DataFrame(posts)

    # write to GCS data bucket
    data_bucket = os.environ['DATA_BUCKET']
    destination_blob = os.environ['REDDIT_INGEST_DATA_PATH']
    destination_blob = format_hive_partition(destination_blob, subreddit=sub)
    GcpMethods().write_gcs(bucket=data_bucket, blob=destination_blob, blob_data=post_df)

    # write generic message to pubsub to trigger spotify function
    spotify_payload = json.dumps({"reddit_blob": destination_blob, "subreddit": sub})
    GcpMethods().pubsub_push(message=spotify_payload)

    return 200 

def spotify_handler(event, context):

    # parse incoming pubsub message, set env vars, read reddit data from GCS
    payload = GcpMethods().pubsub_read(event=event)
    payload = json.loads(payload)
    data_bucket, source_blob = os.environ['DATA_BUCKET'], payload["reddit_blob"] 
    reddit_data = GcpMethods().read_gcs_tsv(bucket=data_bucket, blob=source_blob)

    #instantiate spotify object
    spot = Spotify()

    # search URIs of tracks, update df. then pass to a slim df, drop main reddit df 
    reddit_data['track_id'] = reddit_data.apply(lambda row: None if row.artist is None or row.track is None else spot.get_track_id(artist=row.artist, track=row.track), axis=1)
    comb_df = reddit_data[['post_id', 'track_id']]
    del reddit_data

    # get distinct track ids and look up further track information on spotify
    spot_data = list(comb_df['track_id'].drop_duplicates().dropna())
    df_dim_track = pd.DataFrame(spot.get_track_details(ids=spot_data))

    # join track dim df to main df having post keys 
    # explicitly cast as type str
    df_dim_track['track_id'], comb_df['track_id'] = df_dim_track['track_id'].astype(str), comb_df['track_id'].astype(str)
    comb_df = comb_df.merge(df_dim_track, how='left', on='track_id', suffixes=(None, "_dim")) 

    # write the track dim table (df) to gcs
    destination_blob = os.environ['SPOTIFY_INGEST_DATA_PATH']
    destination_blob = format_hive_partition(destination_blob, subreddit=payload['subreddit'])
    GcpMethods().write_gcs(bucket=data_bucket, blob=destination_blob, blob_data=comb_df)

    return 200

# local running
if __name__=='__main__':
    # get config from GCS. pass to next function 
    event = {}
    event['body'] = config_handler(None, None)
    # pass config to reddit handler to ingest reddit stuff
    reddit_handler(event, None)
    # spotify handler reads from gcs
    spotify_handler(None, None)
