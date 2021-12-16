class IssuesController < ApplicationController
  default_search_scope :issues

  before_filter :find_issue, :only => [:show, :edit, :update]
  before_filter :find_issues, :only => [:bulk_edit, :bulk_update, :destroy]
  before_filter :find_project, :only => [:new, :create, :update_form]
  before_filter :authorize, :except => [:index]
  before_filter :find_optional_project, :only => [:index]
  before_filter :check_for_default_issue_status, :only => [:new, :create]
  before_filter :build_new_issue_from_params, :only => [:new, :create, :update_form]
  accept_rss_auth :index, :show
  accept_api_auth :index, :show, :create, :update, :destroy

  rescue_from Query::StatementInvalid, :with => :query_statement_invalid

  def bulk_update
    @issues.sort!
    @copy = params[:copy].present?
    attributes = parse_params_for_bulk_issue_attributes(params)

    unsaved_issues = []
    saved_issues = []

    if @copy && params[:copy_subtasks].present?
      # Descendant issues will be copied with the parent task
      # Don't copy them twice
      @issues.reject! {|issue| @issues.detect {|other| issue.is_descendant_of?(other)}}
    end

    @issues.each do |orig_issue|
      orig_issue.reload
      if @copy
        issue = orig_issue.copy({},
          :attachments => params[:copy_attachments].present?,
          :subtasks => params[:copy_subtasks].present?
        )
      else
        issue = orig_issue
      end

      journal = issue.init_journal(User.current, params[:notes])
      issue.safe_attributes = attributes
      call_hook(:controller_issues_bulk_edit_before_save, { :params => params, :issue => issue })
      if issue.save
        saved_issues << issue
      else
        unsaved_issues << orig_issue
      end
    end

    if unsaved_issues.empty?
      flash[:notice] = l(:notice_successful_update) unless saved_issues.empty?
      if params[:follow]
        if @issues.size == 1 && saved_issues.size == 1
          redirect_to issue_path(saved_issues.first)
        elsif saved_issues.map(&:project).uniq.size == 1
          redirect_to project_issues_path(saved_issues.map(&:project).first)
        end
      else
        redirect_back_or_default _project_issues_path(@project)
      end
    else
      @saved_issues = @issues
      @unsaved_issues = unsaved_issues
      @issues = Issue.visible.where(:id => @unsaved_issues.map(&:id)).all bulk_edit
      render :action => 'bulk_edit'
    end
  end
end
