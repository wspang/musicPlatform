from api_methods import reddit_obj
    
class Reddit:
    def __init__(self):

    # Create the Reddit object (read only) to use in API calls
        self.REDDIT = reddit_obj()
        return
    
    def get_posts(self, subreddit_name, post_count):
        # retrieve post titles  from subreddits and return as a list to process.
        posts = [{"post_id": r.id, "title": r.title, "subreddit": subreddit_name, "score": r.score, "upvote_ratio": r.upvote_ratio} for r in self.REDDIT.subreddit(subreddit_name).hot(limit=post_count)]
        return posts 
    
    def parse_title(self, title):
        """Try to parse a title for a song name and artist
           This is based off common naming convention used in subreddit... no ML yet :)
           Rules:::
               - any post starting with [FRESH] will follow with <ARTIST> - <SONG> ...
               - posts with <NAME> - <WORDS> is almost always a song
               - any titles with `ft.` will have a feature, meaning a song"""
        # Rule One: look for a dash within post title or if it is a discussion post
        dash_loc = title.find('-')
        if dash_loc == -1 or title[:12].lower() == '[discussion]':
            song_post = {"artist": None, "track": None}
            return song_post
        else:
            pass
        # Look out for content after brackets
        if title[0] == "[":
            artist = title[(title.find(']')+2) : (dash_loc)]
            song = title[(dash_loc+1) :]
        # Look out for a regular song post
        else:
            artist = title[: dash_loc]
            song = title[dash_loc+1 :]
    
        # Now parse any extra off the end of a post
        info_loc = title.rfind('(')
        # has -1 index if there is none. If it comes after dash, it is info.
        song = song if info_loc < dash_loc else title[(dash_loc+1) : (info_loc)]
        # trim more extra off if in brackets
        song = song if song.find('[') == -1 else song[: song.find('[')-1]
        
        # handle features on a track.
        artist = artist if "ft." not in artist else artist[: artist.find('ft.')]
        
        # return dictionary of song posts
        song_post = {"artist":artist, "track": song}
        return song_post
