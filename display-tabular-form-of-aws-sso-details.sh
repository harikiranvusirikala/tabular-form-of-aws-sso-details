# Retrieve the ARN and identity store ID of the SSO instances
instance_arn=$(aws sso-admin list-instances | jq -r '.Instances[].InstanceArn')
instance_store_id=$(aws sso-admin list-instances | jq -r '.Instances[].IdentityStoreId')

# Define a list of account IDs to process
accounts_ids='''
008796491234
939078521234
'''

# Iterate over each account ID
for account_id in ${accounts_ids}; do

  # Remove any existing 'test' file and print the current account
  rm -f test
  echo "* Account ${account_id}"

  # Retrieve the permission sets provisioned to the account and store the assignments in the 'test' file
  for permission_set_arn in $(aws sso-admin list-permission-sets-provisioned-to-account \
    --instance-arn ${instance_arn} \
    --account-id ${account_id} | jq -r '.PermissionSets[]'); do
    aws sso-admin list-account-assignments \
      --instance-arn ${instance_arn} \
      --account-id ${account_id} \
      --permission-set-arn $permission_set_arn | jq -r '(.AccountAssignments[] | [.PermissionSetArn, .PrincipalType, .PrincipalId]) | @tsv' >>test
  done

  # Print the header for the user details
  echo UserName EmailId PermissionSetName GroupName

  # Read each line from the 'test' file
  while read line; do
    permission_set_arn=$(echo $line | cut -d' ' -f1)
    principal_type=$(echo $line | cut -d' ' -f2)
    principal_id=$(echo $line | cut -d' ' -f3)

    # Retrieve the name of the permission set
    permission_set_name=$(aws sso-admin describe-permission-set --instance-arn ${instance_arn} --permission-set-arn $permission_set_arn | jq -r '.PermissionSet.Name')

    # If the principal type is a group, retrieve its details
    if [[ $principal_type == "GROUP" ]]; then
      group_name=$(aws identitystore describe-group --identity-store-id ${instance_store_id} --group-id $principal_id | jq -r '.DisplayName')

      # Iterate over the user IDs in the group
      for userId in $(aws identitystore list-group-memberships --identity-store-id ${instance_store_id} --group-id $principal_id | jq -r '.GroupMemberships[].MemberId.UserId'); do

        # Retrieve user details and print them
        response=$(aws identitystore describe-user --identity-store-id ${instance_store_id} --user-id ${userId})
        user_id=$(echo $response | jq -r '.UserId')
        user_name=$(echo $response | jq -r '.UserName')
        display_name=$(echo $response | jq -r '.DisplayName')
        email=$(echo $response | jq -r '.Emails[].Value')
        echo $user_name $email $permission_set_name $group_name
      done
    fi

  done <test

  # Remove the 'test' file for the next iteration
  rm -f test
done