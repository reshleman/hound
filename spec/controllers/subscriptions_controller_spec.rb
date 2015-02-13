require "spec_helper"

describe SubscriptionsController, "#create" do
  context "when subscription succeeds" do
    it "subscribes the user to the repo" do
      token = "usergithubtoken"
      repo = create(:repo, private: true)
      membership = create(:membership, repo: repo)
      activator = double(:repo_activator, activate: true)
      repo_subscriber = double("RepoSubscriber", subscribe: true)
      allow(RepoActivator).to receive(:new).and_return(activator)
      allow(RepoSubscriber).to receive(:new).and_return(repo_subscriber)
      allow(JobQueue).to receive(:push)
      stub_sign_in(membership.user, token)

      post(
        :create,
        repo_id: repo.id,
        card_token: "cardtoken",
        email_address: "jimtom@example.com",
        format: :json
      )

      expect(activator).to have_received(:activate)
      expect(repo_subscriber).to have_received(:subscribe)
      expect(RepoActivator).to have_received(:new).
        with(repo: repo, github_token: token)
      expect(RepoSubscriber).to have_received(:new).
        with(repo, membership.user, "cardtoken")
      expect(analytics).to have_tracked("Repo Activated").
        for_user(membership.user).
        with(
          properties: {
            name: repo.name,
            private: true,
            revenue: repo.plan_price,
          }
        )
    end

    it "updates the current user's email address" do
      user = create(:user, email_address: nil)
      repo = create(:repo)
      user.repos << repo
      activator = double(:repo_activator, activate: true)
      repo_subscriber = double("RepoSubscriber", subscribe: true)
      allow(RepoActivator).to receive(:new).and_return(activator)
      allow(RepoSubscriber).to receive(:new).and_return(repo_subscriber)
      allow(JobQueue).to receive(:push)
      stub_sign_in(user)

      post(
        :create,
        repo_id: repo.id,
        card_token: "cardtoken",
        email_address: "jimtom@example.com",
        format: :json
      )

      expect(user.reload.email_address).to eq "jimtom@example.com"
    end
  end

  context "when subscription fails" do
    it "deactivates repo" do
      membership = create(:membership)
      repo = membership.repo
      activator = double(
        "RepoActivator",
        activate: true,
        deactivate: nil,
        errors: []
      )
      repo_subscriber = double(
        "RepoSubscriber",
        subscribe: nil,
        errors: ["error"]
      )
      allow(RepoActivator).to receive(:new).and_return(activator)
      allow(RepoSubscriber).to receive(:new).and_return(repo_subscriber)
      stub_sign_in(membership.user)

      post :create, repo_id: repo.id, format: :json

      expect(activator).to have_received(:deactivate)
    end

    it "returns 502 with errors" do
      membership = create(:membership)
      repo = membership.repo
      activator = double(
        "RepoActivator",
        activate: true,
        deactivate: nil,
        errors: []
      )
      error_message = "Stripe failure"
      repo_subscriber = double(
        "RepoSubscriber",
        subscribe: nil,
        errors: [error_message]
      )
      allow(RepoActivator).to receive(:new).and_return(activator)
      allow(RepoSubscriber).to receive(:new).and_return(repo_subscriber)
      stub_sign_in(membership.user)

      post :create, repo_id: repo.id, format: :json

      response_body = JSON.parse(response.body)
      expect(response.code).to eq "502"
      expect(response_body["errors"]).to match_array([error_message])
    end
  end
end

describe SubscriptionsController, "#destroy" do
  it "deletes subscription associated with subscribing user" do
    token = "usertoken"
    current_user = create(:user)
    subscribed_user = create(:user)
    repo = create(:repo, private: true)
    create(:membership, repo: repo, user: current_user)
    create(:subscription, repo: repo, user: subscribed_user)
    activator = double(:repo_activator, deactivate: true)
    allow(RepoActivator).to receive(:new).and_return(activator)
    allow(RepoSubscriber).to receive(:unsubscribe).and_return(true)
    stub_sign_in(current_user, token)

    delete(
      :destroy,
      repo_id: repo.id,
      card_token: "cardtoken",
      format: :json
    )

    expect(activator).to have_received(:deactivate)
    expect(RepoActivator).to have_received(:new).
      with(repo: repo, github_token: token)
    expect(RepoSubscriber).to have_received(:unsubscribe).
      with(repo, subscribed_user)
    expect(analytics).to have_tracked("Repo Deactivated").
      for_user(current_user).
      with(
        properties: {
          name: repo.name,
          private: true,
          revenue: -repo.plan_price,
        }
      )
  end
end
