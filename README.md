# About
fancy third person for gmod<br>
<br>
be warned, this is badly coded and has shoddy solutions for some things due to it being shared<br>
because of this, it is also required to be installed on servers for it to work for clients<br>
<br>
Additionally, clients wishing to be able to switch the focused shoulder need to bind the key manually via the ``cl_thirdperson_switchshoulder`` convar
this is done by finding your desired key's [enum](https://wiki.facepunch.com/gmod/Enums/BUTTON_CODE), then setting the convar to it

# cvars
* ``cl_thirdperson_enable`` - (``0/1``)
  * Sets whether thirdperson is enabled on clientside or not.
* ``cl_thirdperson_offset_horizontal`` - (``-10 <--> 10``)
  * Modifies the cameras horizontal offset, affecting shoulder/crouch offset.
* ``cl_thirdperson_offset_vertical`` - (``0 <--> 15``)
  * Modifies the cameras vertical offset.
* ``cl_thirdperson_offset_distance`` - (``0 <--> 100``)
  * Modifies the cameras distance.
* ``cl_thirdperson_fpaiming`` - (``0/1``)
  * If this is enabled, the players thirdperson camera will switch to firstperson when aiming with a weapon.
* ``cl_thirdperson_enforce_hook`` - (``0/1``)
  * If this is enabled, all other CalcView hooks will be overriden by the thirdperson hook.
* ``cl_thirdperson_switchshoulder`` - (``int``)
  * Not a normal convar, controls the key used to switch the cameras focused shoulder.
* ``sv_thirdperson_allowed`` - (``0/1``)
  * Sets whether thirdperson is allowed for clients or not.
* ``sv_thirdperson_antipeek`` - (``0/1``)
  * Sets whether players that are out of view are hidden for clients using thirdperson or not.

# concommands
* ``cl_thirdperson_toggle``
  * Toggles thirdperson on and off.

# Features
* Dynamic FOV
* Accurate aim offset
* Crouch jump smoothing
* One-to-one accurate spread/recoil for all weapon bases
* First-person aiming similar to MGS V (optional)
* Anti-peek (optional)
* Shoulder system (optional)