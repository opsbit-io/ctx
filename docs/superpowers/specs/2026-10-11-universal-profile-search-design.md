# Universal Profile Search Design

## Goal

Allow users to find profiles already discovered by CTX using provider metadata, not
only profile and folder names. Search stays local, immediate, and independent of
connection state.

## Scope

The first release searches existing `CloudProfile` values discovered from AWS CLI
configuration, GCP configurations, Azure subscriptions, and kubeconfig contexts.
It does not query a provider, start authentication, read secret values, or create a
second persistent index.

Searchable metadata:

- profile name and provider name;
- account, project, subscription, or cluster identifier;
- role, identity, tenant, or Kubernetes user;
- region or namespace;
- SSO start URL;
- linked AWS profile name for Kubernetes contexts.

Access Key ID is deferred until the AWS credential-management model exists. Secret
keys, tokens, and raw credential values must never enter the search index.

## Architecture

Add one provider-neutral search matcher in CTXCore. It receives a `CloudProfile` and
a user query, normalizes them, and returns whether every non-empty query token occurs
in at least one searchable field. `ProfileGrouping` remains responsible only for
preserving the provider/folder tree and filtering profiles through that matcher.

Both the main sidebar and menu-bar UI already call `ProfileGrouping`, so they gain
identical behavior without duplicated view logic. No provider-specific commands or
configuration writers change.

## Matching Rules

- Trim surrounding whitespace and compare case-insensitively.
- Split a query on whitespace; all tokens must match, possibly across different
  fields. For example, `aws 6438 prod` can match provider, account ID, and name.
- Also compare a compact alphanumeric representation so punctuation in identifiers
  does not prevent a match. For example, `643-869` matches `643869`.
- A matching folder name or provider keeps all profiles in that folder, preserving
  current behavior. Otherwise, only matching profiles remain.
- An empty query returns the original groups unchanged.

## Safety and Privacy

- Search performs no network calls and runs no CLI command.
- Search uses metadata already held by `CloudProfile`.
- No credential file is read by the UI or search matcher.
- No query or indexed value is logged or persisted.
- Existing AWS, GCP, Azure, and Kubernetes connection behavior is unchanged.

## Testing

Add focused tests for:

- AWS account ID and role;
- GCP project ID and account identity;
- Azure subscription and tenant;
- Kubernetes cluster, user, namespace, and linked AWS profile;
- case-insensitive and punctuation-insensitive matching;
- multi-token AND matching;
- folder matches retaining all children;
- unrelated queries removing empty folders and providers;
- parity between the shared grouping used by the sidebar and menu bar.

Before delivery, run the Xcode build plus the repository verification commands. Build
a fresh signed application bundle and verify that its executable differs from the old
build before replacing the local application. Installation must not modify any cloud
configuration or credential file.

## Deferred Work

AWS credential creation, replacement, masking, Keychain policy, Access Key ID search,
`credential_process`, and Assume Role management belong to the next independently
reviewed design. They are not part of this search change.
