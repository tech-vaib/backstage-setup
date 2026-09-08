#Modify app-config.yaml

auth:
  environment: development

  providers:
    github:
      development:
        clientId: ${AUTH_GITHUB_CLIENT_ID}
        clientSecret: ${AUTH_GITHUB_CLIENT_SECRET}

        signIn:
          resolvers:
            - resolver: usernameMatchingUserEntityName



In GitHub, create an OAuth App.
Homepage URL:
https://backstage.company.com

Authorization callback URL:
https://backstage.company.com/api/auth/github/handler/frame


            export AUTH_GITHUB_CLIENT_ID="your-client-id"
export AUTH_GITHUB_CLIENT_SECRET="your-client-secret"


### Install the GitHub auth backend module
yarn --cwd packages/backend add @backstage/plugin-auth-backend-module-github-provider

Then modify:

packages/backend/src/index.ts
add:
backend.add(import('@backstage/plugin-auth-backend'));

backend.add(
  import('@backstage/plugin-auth-backend-module-github-provider'),
);



## change login

Your current Backstage app may have something like:

providers={[
  'guest',
]}


You want GitHub instead.

With the current frontend system, Backstage's documentation uses githubAuthApiRef and a GitHub provider on the SignInPage.

Conceptually:

import { githubAuthApiRef } from '@backstage/core-plugin-api';

and:

<SignInPage
  {...props}
  provider={{
    id: 'github-auth-provider',
    title: 'GitHub',
    message: 'Sign in using GitHub',
    apiRef: githubAuthApiRef,
  }}
/>

###The most important part: User mapping
