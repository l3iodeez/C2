class ProposalDecorator < Draper::Decorator
  delegate_all

  def number_approved
    object.approvals.approved.count
  end

  def total_approvers
    object.approvals.count
  end

  def approvals_by_status
    # Override default scope
    object.user_approvals.reorder(
      # http://stackoverflow.com/a/6332081/358804
      <<-SQL
        CASE approvals.status
        WHEN 'approved' THEN 1
        WHEN 'rejected' THEN 2
        WHEN 'actionable' THEN 3
        ELSE 4
        END
      SQL
    )
  end

  def approvals_in_list_order
    approvals_by_status
  end

  def display_status
    if object.pending?
      'pending approval'
    else
      object.status
    end
  end

  def generate_status_message
    if object.approvals.where.not(status: 'pending').empty?
      progress_status_message
    else
      completed_status_message
    end
  end

  def completed_status_message
    "All #{number_approved} of #{total_approvers} approvals have been received. Please move forward with the purchase  of Cart ##{object.public_identifier}."
  end

  def progress_status_message
    "#{number_approved} of #{total_approvers} approved."
  end

  def email_subject
    "Request #{proposal.public_identifier}"
  end

  def email_msg_id
    "<proposal-#{self.id}@#{DEFAULT_URL_HOST}>"
  end
end
