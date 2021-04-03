from api_methods import spotify_auth
import requests 

# spotify APIs wrapped into functions
class Spotify():
    def __init__(self):
        self.authentication_type="client"  # defaults to client. change to user if doing account session
        self.token = spotify_auth(grant_type=self.authentication_type)
        self.header = {'Authorization': f'Bearer {self.token}'}
        return

    def get_track_id(self, artist, track):
        # given an artist and song title, return the top track uri
        kw = f"track:{track}%20artist:{artist}"
        url = f"https://api.spotify.com/v1/search?q={kw}&type=track&limit=1"
        r = requests.get(url=url, headers=self.header)
        
        # parse for track uri
        try:
            track_id = r.json()['tracks']['items'][0]['id']
            return track_id 
        except Exception:
            return None

    def parse_track_details(self, data:dict):
        # no api call. rather, parse the get track json
        parsed = {}
        # get track name, popularity
        parsed['track_name'], parsed['track_popularity'], parsed['track_id'] = data['name'], data['popularity'], data['id']
        # get album details
        try:
            parsed['album_name'], parsed['album_id'] = data['album']['name'], data['album']['id']
        except KeyError:
            parsed['album_name'], parsed['album_id'] = None, None
        # get artist details
        try: 
            parsed['artist_name'], parsed['artist_id'] = data['artists'][0]['name'], data['artists'][0]['id'] 
        except KeyError:
            parsed['artist_name'], parsed['artist_id'] = None, None
        # get supporting artists
        parsed['supporting_artists'] = ", ".join([a['name'] for a in data['artists']][1:]) if len(data['artists']) > 1 else None
        # track features
        # Mood:
        parsed['danceability'], parsed['energy'], parsed['valence'], parsed['tempo'] = data['danceability'], data['energy'], data['valence'], data['tempo']
        # Properties:
        parsed['loudness'], parsed['speechiness'], parsed['instrumentalness'] = data['loudness'], data['speechiness'], data['instrumentalness'] 
        # Context:
        parsed['acousticness'], parsed['liveness'], parsed['duration_ms'] = data['acousticness'], data['liveness'], data['duration_ms'] 
        # return parsed dictionary
        return parsed

    def get_track_details(self, ids:list):
        # Given a list of track IDs, return greater details about it like popularity and 'musicality'
        raw_data = []
        # break tracks into batches of 50 for api constraint
        for t in range(0, len(ids), 50):
            id_formatter = ",".join(ids[t:t+50])
            # call first api for top level track details
            url = f"https://api.spotify.com/v1/tracks?ids={id_formatter}"
            track_response = requests.get(url=url, headers=self.header).json()['tracks']
            # call second api for in depth audio features
            url = f"https://api.spotify.com/v1/audio-features?ids={id_formatter}"
            feature_response = requests.get(url=url, headers=self.header).json()['audio_features']
            # zip the track and features list together to parse. maintains order from track id list.
            zipped_response = [{**u, **v} for u,v in zip(track_response, feature_response)] 
            # pass to parser function to reform dictionary
            response = [self.parse_track_details(r) for r in zipped_response]
            raw_data.extend(response)
        return raw_data

    def update_playlist(self, playlist, tracks):
        # given a list of track uris, replace playlist with all those tracks
        url = f"https://api.spotify.com/v1/playlists/{playlist}/tracks"
        requests.put(url=url, headers=self.header, json={"uris": tracks})
        return
