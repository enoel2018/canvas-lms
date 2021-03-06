# frozen_string_literal: true

#
# Copyright (C) 2017 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

require File.expand_path(File.dirname(__FILE__) + '/../../helpers/discussions_common')

describe "discussions" do
  include_context "in-process server selenium tests"
  include DiscussionsCommon

  let(:course) { course_model.tap{|course| course.offer!} }
  let(:default_section) { course.default_section }
  let(:new_section) { course.course_sections.create!(name: "section 2") }
  let(:group) do
    course.groups.create!(name: 'group',
                          group_category: group_category).tap do |g|
      g.add_user(student, 'accepted', nil)
    end
  end
  let(:student) { student_in_course(course: course, name: 'student', active_all: true).user }
  let(:teacher) { teacher_in_course(course: course, name: 'teacher', active_all: true).user }
  let(:assignment_group) { course.assignment_groups.create!(name: 'assignment group') }
  let(:group_category) { course.group_categories.create!(name: 'group category') }
  let(:assignment) { course.assignments.create!(
      name: 'assignment',
      #submission_types: 'discussion_topic',
      assignment_group: assignment_group
  ) }

  context "on the new page" do
    let(:url) { "/courses/#{course.id}/discussion_topics/new" }

    before(:each) do
      stub_rcs_config
    end

    context "as a teacher" do
      before(:each) do
        user_session(teacher)
      end

      it "should add an attachment to a new topic", priority: "1", test_id: 150466 do
        topic_title = 'new topic with file'
        get url
        replace_content(f('input[name=title]'), topic_title)
        add_attachment_and_validate
        expect(DiscussionTopic.where(title: topic_title).first.attachment_id).to be_present
      end

      it "should create a podcast enabled topic", priority: "1", test_id: 150467 do
        get url
        replace_content(f('input[name=title]'), "This is my test title")
        type_in_tiny('textarea[name=message]', 'This is the discussion description.')

        f('input[type=checkbox][name=podcast_enabled]').click
        expect_new_page_load { submit_form('.form-actions') }
        #get "/courses/#{course.id}/discussion_topics"
        # TODO: talk to UI, figure out what to display here
        # f('.discussion-topic .icon-rss').should be_displayed
        expect(DiscussionTopic.last.podcast_enabled).to be_truthy
      end

      context "graded" do
        it "should allow creating multiple due dates", priority: "1", test_id: 150468 do
          assignment_group
          group_category
          new_section
          get url

          f('input[type=checkbox][name="assignment[set_assignment]"]').click

          due_at1 = Time.zone.now + 3.days
          due_at2 = Time.zone.now + 4.days

          fj('.ic-tokeninput-input:first').send_keys(default_section.name)
          wait_for_ajaximations
          fj(".ic-tokeninput-option:visible:first").click
          wait_for_ajaximations
          fj(".datePickerDateField[data-date-type='due_at']:first").send_keys(format_date_for_view(due_at1))

          f('#add_due_date').click
          wait_for_ajaximations

          fj('.ic-tokeninput-input:last').send_keys(new_section.name)
          wait_for_ajaximations
          fj(".ic-tokeninput-option:visible:first").click
          wait_for_ajaximations
          fj(".datePickerDateField[data-date-type='due_at']:last").send_keys(format_date_for_view(due_at2))

          expect_new_page_load { f('.form-actions button[type=submit]').click }
          topic = DiscussionTopic.last

          overrides = topic.assignment.assignment_overrides
          expect(overrides.count).to eq 2
          default_override = overrides.detect { |o| o.set_id == default_section.id }
          expect(default_override.due_at.to_date).to eq due_at1.to_date
          other_override = overrides.detect { |o| o.set_id == new_section.id }
          expect(other_override.due_at.to_date).to eq due_at2.to_date
        end

        it "should validate that a group category is selected", priority: "1", test_id: 150469 do
          assignment_group
          get url

          f('input[type=checkbox][name="assignment[set_assignment]"]').click
          f('#has_group_category').click
          close_visible_dialog
          f('#edit_discussion_form_buttons .btn-primary[type=submit]').click
          wait_for_ajaximations
          error_box = f("div[role='alert'] .error_text")
          expect(error_box.text).to eq "Please create a group set"
        end
      end

      context "post to sis default setting" do
        before do
          @account = @course.root_account
          @account.set_feature_flag! 'post_grades', 'on'
        end

        it "should default to post grades if account setting is enabled" do
          @account.settings[:sis_default_grade_export] = {:locked => false, :value => true}
          @account.save!

          get url
          f('input[type=checkbox][name="assignment[set_assignment]"]').click

          expect(is_checked('#assignment_post_to_sis')).to be_truthy
        end

        it "should not default to post grades if account setting is not enabled" do
          get url
          f('input[type=checkbox][name="assignment[set_assignment]"]').click

          expect(is_checked('#assignment_post_to_sis')).to be_falsey
        end
      end
    end

    context "as a student" do
      before(:each) do
        user_session(student)
      end

      it "should allow a student to create a discussion", priority: "1", test_id: 150471 do
        get url
        replace_content(f('input[name=title]'), "Student Discussion")
        type_in_tiny('textarea[name=message]', 'This is the discussion description.')
        expect_new_page_load {submit_form('.form-actions')}
        expect(f('.discussion-title').text).to eq "Student Discussion"
        expect(f("#content")).not_to contain_css('#topic_publish_button')
      end

      it 'should not show file attachment if allow_student_forum_attachments is not true', priority: '2', test_id: 223507 do
        skip_if_safari(:alert)
        # given
        course.allow_student_forum_attachments = false
        course.save!
        # expect
        get url
        expect(f("#content")).not_to contain_css('#disussion_attachment_uploaded_data')
      end

      it 'should show file attachment if allow_student_forum_attachments is true', priority: '2' do
        skip_if_safari(:alert)
        # given
        course.allow_student_forum_attachments = true
        course.save!
        # expect
        get url
        expect(f('#discussion_attachment_uploaded_data')).not_to be_nil
      end

      context 'in a group' do
        let(:url) { "/groups/#{group.id}/discussion_topics/new" }

        it 'should not show file attachment if allow_student_forum_attachments is not true', priority: '2', test_id: 223508 do
          skip_if_safari(:alert)
          # given
          course.allow_student_forum_attachments = false
          course.save!
          # expect
          get url
          expect(f("#content")).not_to contain_css('label[for=discussion_attachment_uploaded_data]')
        end

        it 'should show file attachment if allow_student_forum_attachments is true', priority: '2' do
          skip_if_safari(:alert)
          # given
          course.allow_student_forum_attachments = true
          course.save!
          # expect
          get url
          expect(f('label[for=discussion_attachment_uploaded_data]')).to be_displayed
        end
      end
    end
  end
end
