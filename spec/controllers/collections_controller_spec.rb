# Copyright 2011-2015, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
# 
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed 
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the 
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

require 'spec_helper'

describe Admin::CollectionsController, type: :controller do
  render_views

  describe "#manage" do
    let!(:collection) { FactoryGirl.create(:collection) }
    before(:each) do
      request.env["HTTP_REFERER"] = '/'
      login_as(:administrator)
    end

    it "should add users to manager role" do
      manager = FactoryGirl.create(:manager)
      put 'update', id: collection.id, submit_add_manager: 'Add', add_manager: manager.username
      collection.reload
      manager.should be_in(collection.managers)
    end

    it "should not add users to manager role" do
      user = FactoryGirl.create(:user)
      put 'update', id: collection.id, submit_add_manager: 'Add', add_manager: user.username
      collection.reload
      user.should_not be_in(collection.managers)
      flash[:notice].should_not be_empty
    end

    it "should remove users from manager role" do
      #initial_manager = FactoryGirl.create(:manager).username
      collection.managers += [FactoryGirl.create(:manager).username]
      collection.save!
      manager = User.where(username: collection.managers.first).first
      put 'update', id: collection.id, remove_manager: manager.username
      collection.reload
      manager.should_not be_in(collection.managers)
    end
  end

  describe "#edit" do
    let!(:collection) { FactoryGirl.create(:collection) }
    before(:each) do
      request.env["HTTP_REFERER"] = '/'
    end

    it "should add users to editor role" do
      login_as(:administrator)
      editor = FactoryGirl.build(:user)
      put 'update', id: collection.id, submit_add_editor: 'Add', add_editor: editor.username
      collection.reload
      editor.should be_in(collection.editors)
    end

    it "should remove users from editor role" do
      login_as(:administrator)
      editor = User.where(username: collection.editors.first).first
      put 'update', id: collection.id, remove_editor: editor.username
      collection.reload
      editor.should_not be_in(collection.editors)
    end
  end

  describe "#deposit" do
    let!(:collection) { FactoryGirl.create(:collection) }
    before(:each) do
      request.env["HTTP_REFERER"] = '/'
    end

    it "should add users to depositor role" do
      login_as(:administrator)
      depositor = FactoryGirl.build(:user)
      put 'update', id: collection.id, submit_add_depositor: 'Add', add_depositor: depositor.username
      collection.reload
      depositor.should be_in(collection.depositors)
    end

    it "should remove users from depositor role" do
      login_as(:administrator)
      depositor = User.where(username: collection.depositors.first).first
      put 'update', id: collection.id, remove_depositor: depositor.username
      collection.reload
      depositor.should_not be_in(collection.depositors)
    end
  end

  describe "#show" do
    let!(:collection) { FactoryGirl.create(:collection) }

    it "should allow access to managers" do
      login_user(collection.managers.first)
      get 'show', id: collection.id
      response.should be_ok
    end

    it "should redirect to collections index when manager doesn't have access" do
      login_as(:manager)
      get 'show', id: collection.id
      response.should redirect_to(admin_collections_path)
    end
  end

  describe "#create" do
    let!(:collection) { FactoryGirl.create(:collection) }
    before(:each) { login_as(:administrator) } #Login as admin so there will be at least one administrator to get an email
    it "should notify administrators" do
      mock_delay = double('mock_delay').as_null_object 
      NotificationsMailer.stub(:delay).and_return(mock_delay)
      mock_delay.should_receive(:new_collection)
      post 'create', admin_collection: {name: collection.name+'-1', description: collection.description, unit: collection.unit, managers: collection.managers}
    end
    it "should create a new collection" do
      post 'create', admin_collection: {name: collection.name+'-2', description: collection.description, unit: collection.unit, managers: collection.managers}
      expect(JSON.parse(response.body)['id'].class).to eq String
      expect(JSON.parse(response.body)).not_to include('errors')
    end
    it "should return 422 if collection creation failed" do
      post 'create', admin_collection: {name: collection.name+'-3', description: collection.description, unit: collection.unit}
      expect(response.status).to eq(422)
      expect(JSON.parse(response.body)).to include('errors')
      expect(JSON.parse(response.body)["errors"].class).to eq Array
      expect(JSON.parse(response.body)["errors"].first.class).to eq String
    end

  end

  describe "#update" do
    it "should notify administrators if name changed" do
      login_as(:administrator) #Login as admin so there will be at least one administrator to get an email
      mock_delay = double('mock_delay').as_null_object 
      NotificationsMailer.stub(:delay).and_return(mock_delay)
      mock_delay.should_receive(:update_collection)
      @collection = FactoryGirl.create(:collection)
      put 'update', id: @collection.pid, admin_collection: {name: "#{@collection.name}-new", description: @collection.description, unit: @collection.unit}
    end

    context "access controls" do
      let!(:collection) { FactoryGirl.create(:collection)}

      before(:each) do
        login_as(:administrator)
      end 

      it "should not allow empty user" do
        expect{ put 'update', id: collection.pid, submit_add_user: "Add", add_user: "", add_user_display: ""}.not_to change{ collection.reload.default_read_users.size }
      end

      it "should not allow empty class" do
        expect{ put 'update', id: collection.pid, submit_add_class: "Add", add_class: "", add_class_display: ""}.not_to change{ collection.reload.default_read_groups.size }
      end

      it "should update a collection via API" do
        old_description = collection.description
        put 'update', format: 'json', id: collection.pid, admin_collection: {description: collection.description+'new'}
        expect(JSON.parse(response.body)['id'].class).to eq String
        expect(JSON.parse(response.body)).not_to include('errors')
        collection.reload
        expect(collection.description).to eq old_description+'new'
      end
      it "should return 422 if collection update via API failed" do
        allow_any_instance_of(Admin::Collection).to receive(:save).and_return false
        put 'update', format: 'json', id: collection.pid, admin_collection: {description: collection.description+'new'}
        expect(response.status).to eq(422)
        expect(JSON.parse(response.body)).to include('errors')
        expect(JSON.parse(response.body)["errors"].class).to eq Array
        expect(JSON.parse(response.body)["errors"].first.class).to eq String
      end

    end
  end
end
