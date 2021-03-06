class AttachmentsController < ApplicationController
  before_action ->{authorize self.proposal, :can_show!}, only: [:create, :show]
  before_action ->{authorize self.attachment}, only: [:destroy]
  rescue_from Pundit::NotAuthorizedError, with: :auth_errors

  def create
    attachment = self.proposal.attachments.build(attachments_params)
    attachment.user = current_user
    if attachment.save
      flash[:success] = "You successfully added a attachment"
      Dispatcher.deliver_attachment_emails(proposal)
    else
      flash[:error] = attachment.errors.full_messages
    end

    redirect_to proposal
  end

  def destroy
    self.attachment.destroy
    flash[:success] = "Deleted attachment"
    redirect_to proposal_path(attachment.proposal)
  end

  def show
    redirect_to self.attachment.url
  end

  protected
  def proposal
    @cached_proposal ||= Proposal.find(params[:proposal_id])
  end

  def attachment
    @cached_attachment ||= Attachment.find(params[:id])
  end

  def attachments_params
    params.permit(attachment: [:file])[:attachment]
  end

  def auth_errors(exception)
    redirect_to proposals_path, alert: "You are not allowed to add an attachment to that proposal"
  end
end
