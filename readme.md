# Music Tracking Platform
### Overview
Scrape music subreddits for postings. Parse out track and artist from post titles if possible. Look that information up in Spotify to find a track ID. Collect further information on the track.   
Here, will have a daily ingest of reddit music info with corresponding Spotify track to accompany them. Then maybe do some cool stuff with the data.
### Architecture
1. Cloud Scheduler: orchestrate the timing of Cloud Function triggers and BigQuery SPROCs.
2. Pubsub: called from scheduler or cloud function to pass data and trigger other cloud functions.
3. Cloud Functions: handles the data ingest
4. GC Storage: staging data between functions, storing code, and landing raw ingest data
5. BigQuery: external temp table at GCS to ingest new data. Use Sprocs to structure data when in BigQuery.
6. BigQuery ML: When data is in BigQuery, use ML to do ML stuff
7. Data Studio: put a visual on top of all this
### Management
- Terraform is used to manage resource deployments
- TODO: integrate GitOps to trigger Terraform builds on git commits to certain branches
### Why
I like the music and the data 
