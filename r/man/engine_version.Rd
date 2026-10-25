\name{engine_version}
\alias{engine_version}
\title{The version of the Terrio Rust engine}
\usage{
engine_version()
}
\value{
A character scalar: the version of the pinned Terrio Rust crate this package
was built against, as reported by the engine itself.
}
\description{
Reports the version of the Terrio Rust engine (the pinned published
\code{terrio} crate, see \code{src/rust/Cargo.toml}).
}
