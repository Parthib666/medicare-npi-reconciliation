"""BigQuery connection for the notebook.

Signs in with your own Google account through the browser the first time,
then reuses the saved sign-in (stored in your user profile, not in this
project folder, so it never reaches GitHub).

Usage:
    from bq import query
    df = query("SELECT * FROM `npi-reconciliation.work.dq_summary`")
"""

import pydata_google_auth
from google.cloud import bigquery

PROJECT_ID = "npi-reconciliation"
SCOPES = ["https://www.googleapis.com/auth/bigquery"]

_client = None


def client() -> bigquery.Client:
    global _client
    if _client is None:
        credentials = pydata_google_auth.get_user_credentials(
            SCOPES,
            use_local_webserver=True,  # opens your browser to sign in
        )
        _client = bigquery.Client(project=PROJECT_ID, credentials=credentials)
    return _client


def query(sql: str):
    """Run a query and return a pandas DataFrame."""
    # The results here are small, so the plain REST download is fine; this
    # also stops the "BigQuery Storage module not found" warning.
    return client().query(sql).to_dataframe(create_bqstorage_client=False)


if __name__ == "__main__":
    # Connection test: reads the small summary table (a few KB).
    df = query(
        "SELECT check_id, check_name, providers_failed "
        "FROM `npi-reconciliation.work.dq_summary` ORDER BY check_id"
    )
    print(df.to_string(index=False))
    print(f"\nConnected. {len(df)} rows from work.dq_summary.")
