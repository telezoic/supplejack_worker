# The Supplejack code is Crown copyright (C) 2014, New Zealand Government, 
# and is licensed under the GNU General Public License, version 3. 
# See https://github.com/DigitalNZ/supplejack_worker for details. 
# 
# Supplejack was created by DigitalNZ at the National Library of NZ
# and the Department of Internal Affairs. http://digitalnz.org/supplejack

# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :link_check_rule do
    sequence(:source_id)  {|n| "abc#{n}" }
    xpath "/xpath"
    status_codes "404"
  end
end
