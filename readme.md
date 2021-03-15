## Music Tracking Platform
[Find the platform dashboard here on Google Data Studio](https://datastudio.google.com/reporting/9810e424-4fe1-4709-b94f-46ba5964c587). I do not claim to be a data visualist...

### Overview
Scrape the music communities of Reddit to lookup tracks and accompanying information in Spotify. Run daily on a serverless architecture to collect data over time without worry of monitoring scale. Store the data in BigQuery to make available for external applications / uses. Manage the CI/CD of all resources through Terraform for ease in adding future features.  

### Why
Music is a huge driver of my day to day; Whether discovering, reminiscing, sharing, keeping to myself, or recently trying to play. I am always on the look for new sources of music which inspired me to build this project. As a start, it gave me fresh playlists daily, but more than that it is an opportunity to analyze what people in the online communites are listening to. Tracking the music over time will build up a solid library to discover new music and share with others! 

### Architecture
0. Terraform (local): manage resource deployment. *TODO- integrate Cloud Build for triggered releases*
1. Cloud Scheduler: orchestrate the timing of Cloud Function triggers and BigQuery SPROCs.
2. Pubsub: called from scheduler or cloud function to pass data and trigger other cloud functions.
3. Cloud Functions: handles the data ingest
4. GC Storage: staging data between functions, storing code, and landing raw ingest data
5. BigQuery: external tables at GCS to ingest new data. Use *BQ Scheduled Queries* Sprocs to structure data into BigQuery tables.
6. *TODO- BigQuery ML*: When data is in BigQuery, use ML to do ML stuff
7. Data Studio: put a visual on top of all this. Have email subscription to send out and web link to access.

### Diagram
![Diagram](https://github.com/wspang/musicPlatform/blob/dev/platformDiagram.png)
