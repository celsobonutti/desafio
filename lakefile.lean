import Lake
open Lake DSL

package desafio

@[default_target]
lean_lib Desafio

lean_exe desafio where
  root := `Main

extern_lib libleanbtree pkg := do
  let name := nameToStaticLib "leanbtree"
  -- Create directories
  IO.FS.createDirAll (pkg.buildDir / "c")
  IO.FS.createDirAll pkg.staticLibDir
  proc {
    cmd := "clang"
    args := #[
      "-c",
      "-I", (← getLeanIncludeDir).toString,
      "-fPIC",
      "-o", (pkg.buildDir / "c" / "btree.o").toString,
      (pkg.dir / "Desafio" / "btree.c").toString
    ]
  }
  proc {
    cmd := "clang"
    args := #[
      "-c",
      "-I", (← getLeanIncludeDir).toString,
      "-fPIC",
      "-o", (pkg.buildDir / "c" / "BTreeLean.o").toString,
      (pkg.dir / "Desafio" / "BTreeLean.c").toString
    ]
  }
  proc {
    cmd := "ar"
    args := #[
      "rcs",
      (pkg.staticLibDir / name).toString,
      (pkg.buildDir / "c" / "btree.o").toString,
      (pkg.buildDir / "c" / "BTreeLean.o").toString
    ]
  }
  return pure (pkg.staticLibDir / name)
