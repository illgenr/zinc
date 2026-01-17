cmake_minimum_required(VERSION 3.20)

if(NOT DEFINED ZINC_SOURCE_DIR)
  get_filename_component(_script_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
  get_filename_component(ZINC_SOURCE_DIR "${_script_dir}" DIRECTORY)
endif()

function(assert_file_exists path)
  if(NOT EXISTS "${path}")
    message(FATAL_ERROR "Expected file to exist: ${path}")
  endif()
endfunction()

function(png_get_dimensions png_path out_width out_height)
  assert_file_exists("${png_path}")

  file(READ "${png_path}" _header_hex HEX LIMIT 24)
  string(TOUPPER "${_header_hex}" _header_hex)

  string(SUBSTRING "${_header_hex}" 0 16 _sig)
  if(NOT _sig STREQUAL "89504E470D0A1A0A")
    message(FATAL_ERROR "Invalid PNG signature: ${png_path}")
  endif()

  # PNG IHDR: width/height are big-endian u32 at bytes 16..23.
  string(SUBSTRING "${_header_hex}" 32 8 _width_hex)
  string(SUBSTRING "${_header_hex}" 40 8 _height_hex)

  math(EXPR _width "0x${_width_hex}")
  math(EXPR _height "0x${_height_hex}")

  set("${out_width}" "${_width}" PARENT_SCOPE)
  set("${out_height}" "${_height}" PARENT_SCOPE)
endfunction()

set(_manifest_path "${ZINC_SOURCE_DIR}/android/AndroidManifest.xml")
assert_file_exists("${_manifest_path}")
file(READ "${_manifest_path}" _manifest)

foreach(_expected
    "android:icon=\"@mipmap/ic_launcher\""
    "android:roundIcon=\"@mipmap/ic_launcher_round\""
    "android:label=\"Zinc\""
)
  string(FIND "${_manifest}" "${_expected}" _pos)
  if(_pos EQUAL -1)
    message(FATAL_ERROR "Android manifest missing expected attribute: ${_expected}")
  endif()
endforeach()

set(_android_icon_specs
    "mipmap-mdpi|48"
    "mipmap-hdpi|72"
    "mipmap-xhdpi|96"
    "mipmap-xxhdpi|144"
    "mipmap-xxxhdpi|192"
)

foreach(_spec IN LISTS _android_icon_specs)
  string(REPLACE "|" ";" _spec_list "${_spec}")
  list(GET _spec_list 0 _dir)
  list(GET _spec_list 1 _expected_px)

  foreach(_name ic_launcher ic_launcher_round)
    set(_png "${ZINC_SOURCE_DIR}/android/res/${_dir}/${_name}.png")
    png_get_dimensions("${_png}" _w _h)

    if(NOT _w EQUAL _expected_px OR NOT _h EQUAL _expected_px)
      message(FATAL_ERROR "Unexpected dimensions for ${_png}: ${_w}x${_h} (expected ${_expected_px}x${_expected_px})")
    endif()
  endforeach()
endforeach()

message(STATUS "Android launcher icons look consistent.")
