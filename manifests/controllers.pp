# @summary Installs and configures Puppet Bolt for use within the SIMP enviroment
#
# @param local_user_name
#   The username of the local user account to launch bolt commands
#
#   * NOTE: Ensure that this user is local to the host since Puppet will be
#     managing files in the user's home directory.
#
# @param local_group_name
#   The default group name of the local user account
#
# @param local_user_home
#   The full path to the local user's home directory
#
# @author SIMP Team <https://simp-project.com/>
#
class simp_bolt::controllers (
) {

}

