class Proposal < ActiveRecord::Base
  include WorkflowModel
  include ValueHelper
  workflow do
    state :pending do
      event :approve, :transitions_to => :approved
      event :reject, :transitions_to => :rejected
      event :restart, :transitions_to => :pending
    end
    state :approved do
      event :restart, :transitions_to => :pending
    end
    state :rejected do
      event :reject, :transitions_to => :rejected
      event :restart, :transitions_to => :pending
    end
  end

  has_one :cart
  has_one :root_approval, ->{ where(parent_id: nil) }, class_name: 'Approval'
  has_many :approvals
  has_many :user_approvals, ->{ where.not(user_id: nil) }, class_name: 'Approval'

  has_many :approvers, through: :user_approvals, source: :user
  has_many :api_tokens, through: :user_approvals
  has_many :attachments
  has_many :approval_delegates, through: :approvers, source: :outgoing_delegates
  has_many :comments
  has_many :observations
  has_many :observers, through: :observations, source: :user
  belongs_to :client_data, polymorphic: true
  belongs_to :requester, class_name: 'User'

  # The following list also servers as an interface spec for client_datas
  # Note: clients may implement:
  # :fields_for_display
  # :public_identifier
  # :version
  # Note: clients should also implement :version
  delegate :client, to: :client_data_legacy, allow_nil: true

  # TODO validates :requester_id, presence: true

  self.statuses.each do |status|
    scope status, -> { where(status: status) }
  end
  scope :closed, -> { where(status: ['approved', 'rejected']) }

  after_create :update_public_id


  def delegate?(user)
    self.approval_delegates.exists?(assignee_id: user.id)
  end

  def approval_for(user)
    # TODO convert to SQL
    self.approvals.find do |approval|
      approver = approval.user
      approver == user || approver.outgoing_delegates.exists?(assignee_id: user.id)
    end
  end

  # Use this until all clients are migrated to models (and we no longer have a
  # dependence on "Cart"
  def client_data_legacy
    self.client_data || self.cart
  end

  # TODO convert to an association
  def delegates
    self.approval_delegates.map(&:assignee)
  end

  # Returns a list of all users involved with the Proposal.
  def users
    # TODO use SQL
    results = self.approvers + self.observers + self.delegates + [self.requester]
    results.compact
  end

  # returns the Approval
  def add_approver(email)
    user = User.for_email(email)
    approval = Approvals::Individual.new(user: user)
    approval.parent = self.root_approval  # might be nil
    self.approvals << approval
    approval
  end

  def add_observer(email)
    user = User.for_email(email)
    self.observations.create!(user_id: user.id)
  end

  def add_requester(email)
    user = User.for_email(email)
    self.set_requester(user)
  end

  def set_requester(user)
    self.update_attributes!(requester_id: user.id)
  end

  def currently_awaiting_approvals
    self.approvals.actionable
  end

  def currently_awaiting_approvers
    self.approvers.merge(self.currently_awaiting_approvals)
  end

  # delegated, with a fallback
  # TODO refactor to class method in a module
  def delegate_with_default(method)
    data = self.client_data_legacy

    result = nil
    if data && data.respond_to?(method)
      result = data.public_send(method)
    end

    if result.present?
      result
    elsif block_given?
      yield
    else
      result
    end
  end


  ## delegated methods ##

  def public_identifier
    self.delegate_with_default(:public_identifier) { "##{self.id}" }
  end

  def name
    self.delegate_with_default(:name) {
      "Request #{self.public_identifier}"
    }
  end

  def fields_for_display
    # TODO better default
    self.delegate_with_default(:fields_for_display) { [] }
  end

  # Be careful if altering the identifier. You run the risk of "expiring" all
  # pending approval emails
  def version
    [
      self.updated_at.to_i,
      self.client_data_legacy.try(:version)
    ].compact.max
  end

  #######################


  #### state machine methods ####
  def on_rejected_entry(prev_state, event)
    if prev_state.name != :rejected
      Dispatcher.on_proposal_rejected(self)
    end
  end

  def restart
    # Note that none of the state machine's history is stored
    self.api_tokens.update_all(expires_at: Time.now)
    self.initialize_approvals()
    Dispatcher.deliver_new_proposal_emails(self)
  end

  protected
  def update_public_id
    self.update_attribute(:public_id, self.public_identifier)
  end
end
