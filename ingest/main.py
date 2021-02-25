from reddit_ingest import Reddit
from spotify_ingest import Spotify 
from api_methods import GcpMethods
import pandas as pd
import json
import os

def config_handler(event, context):
    # called from scheduler. reads config from GCS to pass to reddit handler. Returns dictionary
    code_bucket = os.environ['CODE_BUCKET']
    blob_path = os.environ['CONFIG_FILE_PATH']
    config_to_pass = GcpMethods().read_gcs_json(bucket=code_bucket, blob=blob_path)
    return config_to_pass

def reddit_handler(event, context):
    # Given reddit / playlist config, read reddit and parse for data. Export to GCS
    payload = event['body']
    post_count = payload['post_count']

    # set reddit and spotify (auth) objects
    redd = Reddit()

    # return list of records to export
    post_output = []

    # ingest titles from reddit, one sub at a time. Can parallelize later.
    for i in payload['playlists']:

        # parse out the subreddit and spotify playlist to look up 
        sub, playlist_uri = i['sub'], i['uri']

        # get reddit posts for the sub
        posts = redd.get_posts(subreddit_name=sub, post_count=post_count)

        # parse post titles for track and artist
        #posts = [post.update(redd.parse_title(post['title'])) for post in posts]
        for post in posts:
            post.update(redd.parse_title(title=post['title']))

        # append to the output list, delete subreddit specific one
        post_output.extend(posts)
        del posts

    # convert to df
    post_df = pd.DataFrame(post_output)

    # write to GCS data bucket
    data_bucket = os.environ['DATA_BUCKET']
    destination_blob = os.environ['REDDIT_INGEST_DATA_PATH']
    GcpMethods().write_gcs(bucket=data_bucket, blob=destination_blob, blob_data=post_df)

    return 200 

def spotify_handler(event, context):

    spot = Spotify()

    # parse out titles from data
    data_bucket, source_blob = os.environ['DATA_BUCKET'], os.environ['REDDIT_INGEST_DATA_PATH']
    df_data = GcpMethods().read_gcs_tsv(bucket=data_bucket, blob=source_blob)
    # deduplicate and rid null's on artist and track parsed
    #spot_data = df_data[['artist', 'track']].drop_duplicates(subset=['artist','track']).dropna()

    # search URIs of tracks, update df. 
    df_data['track_id'] = df_data.apply(lambda row: None if row.artist is None or row.track is None else spot.get_track_id(artist=row.artist, track=row.track), axis=1)
    #spot_data['track_id'] = spot_data.apply(lambda row: spot.get_track_id(artist=row.artist, track=row.track), axis=1)
    #spot_data = spot_data.dropna()
    spot_data = list(df_data['track_id'].drop_duplicates().dropna())

    # Get details of those to join to main DF
    df_dim_track = pd.DataFrame(spot.get_track_details(ids=spot_data))
    
    # write back reddit results to GCS with track id
    output_blob = os.environ['REDDIT_INGEST_DATA_PATH']
    GcpMethods().write_gcs(bucket=data_bucket, blob=output_blob, blob_data=df_data)

    # write the track dim table (df) to gcs
    output_blob = os.environ['SPOTIFY_INGEST_DATA_PATH']
    GcpMethods().write_gcs(bucket=data_bucket, blob=output_blob, blob_data=df_dim_track)

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
