# **NOTE: THIS IS A [PRIVATE](https://github.com/puppetlabs/puppetlabs-stdlib#assert_private) CLASS**
#
# @summary This class is called from simp_bolt for install.
#
class simp_bolt::controller::install {
  assert_private()

  package { $simp_bolt::package_name:
    ensure => present
  }
}
