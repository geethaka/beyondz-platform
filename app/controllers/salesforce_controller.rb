require 'lms'

# The purpose of this controller is to centralize the endpoints for Salesforce triggers.
# Popup windows from SF buttons are still done in the admin area, but triggers notify
# this controller which will take appropriate action.
class SalesforceController < ApplicationController
  def change_apply_now
    if check_magic_token
      params[:yes_list].split(',').each do |id|
        u = User.find_by_salesforce_id(id)
        if u
          u.apply_now_enabled = true
          u.save!
        end
      end
      params[:no_list].split(',').each do |id|
        u = User.find_by_salesforce_id(id)
        if u
          u.apply_now_enabled = false
          u.save!
        end
      end
    end

    render plain: 'OK'
  end

  def record_converted_leads
    if check_magic_token
      params[:changes].split(',').each do |change|
        parts = change.split(':')
        u = User.find_by_salesforce_id(parts[0])
        if u
          u.salesforce_id = parts[1]
          u.save!

          # We may also need to add them to a campaign if certain things
          # are right.
          cm = {}
          cm['CampaignId'] = u.salesforce_campaign_id

          if cm['CampaignId']
            # Can't use client.materialize because it sets the checkboxes to nil
            # instead of false which fails server-side validation. This method
            # works though.
            sf = BeyondZ::Salesforce.new
            client = sf.get_client
            cm['ContactId'] = u.salesforce_id
            client.create('CampaignMember', cm)
          end

          # The apply now enabled *should* be set by the SF triggers
          # but we might want to do it here now anyway to give faster
          # response to the user.
        end
      end
    end

    render plain: 'OK'
  end

  def sync_to_lms
    if check_magic_token
      sf = BeyondZ::Salesforce.new
      client = sf.get_client
      client.materialize('Campaign')
      client.materialize('CampaignMember')
      campaign = SFDC_Models::Campaign.find(params[:campaignId])

      lms = BeyondZ::LMS.new

      members = client.query("
        SELECT
          ContactId, Section_Name_In_LMS__c
        FROM
          CampaignMember
        WHERE
          CampaignId = '#{campaign.Id}'
      ")
      members.each do |member|
        user = User.find_by_salesforce_id(member.ContactId)
        next if user.nil?
        lms.sync_user_logins(user)
        type = 'STUDENT'
        if campaign.Type == 'Leadership Coaches'
          type = 'TA'
        end
        lms.sync_user_course_enrollment(
          user,
          campaign.Target_Course_ID_In_LMS__c[0].to_i,
          type,
          member.Section_Name_In_LMS__c
        )

        user.save!
      end
    end

    render plain: 'OK'
  end

  # a simple filter to keep web crawlers from triggering this
  # needlessly
  def check_magic_token
    params[:magic_token] == Rails.application.secrets.salesforce_magic_token
  end
end