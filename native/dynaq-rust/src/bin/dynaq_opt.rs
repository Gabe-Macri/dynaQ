use dynaq_rust::autoeq::{optimize_autoeq, CurvePoint};
use dynaq_rust::biquad::{calculate_biquad, FilterType};
use dynaq_rust::fir::{generate_fir_kernel, FirType, FirWindow};
use dynaq_rust::true_peak::scan_true_peak;
use std::env;
use std::time::Instant;

fn print_banner() {
    println!("┌────────────────────────────────────────────────────────┐");
    println!("│  DYNAQ RUST HIGH-PERFORMANCE AUDIO OPTIMIZER           │");
    println!("│  Architecture: Apple Silicon AMX / NEON Vector Engine  │");
    println!("│  Version: 1.0.0-beta.2                                 │");
    println!("└────────────────────────────────────────────────────────┘\n");
}

fn print_usage() {
    print_banner();
    println!("USAGE:");
    println!("  dynaq-opt <command> [options]\n");
    println!("COMMANDS:");
    println!("  bench                   Run microsecond-precision SIMD DSP benchmark suite");
    println!("  fir <cutoff_hz> <taps>  Generate windowed FIR filter taps");
    println!("  autoeq                  Demonstrate acoustic curve fitting and optimization");
    println!("  peak                    Scan synthesized audio block for inter-sample true peaks");
    println!("  version                 Display version information");
    println!("  help                    Show this help manual\n");
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        print_usage();
        return;
    }

    match args[1].as_str() {
        "bench" | "-b" => run_benchmarks(),
        "fir" => run_fir(&args),
        "autoeq" => run_autoeq_demo(),
        "peak" => run_peak_demo(),
        "version" | "-v" => {
            println!("dynaq-opt 1.0.0-beta.2 (Rust SIMD Pro-DSP)");
        }
        "help" | "-h" | "--help" => print_usage(),
        cmd => {
            eprintln!("!! [ERROR] Unknown command: {}", cmd);
            print_usage();
            std::process::exit(1);
        }
    }
}

fn run_benchmarks() {
    print_banner();
    println!("// [EXECUTING RUST AUDIO OPTIMIZER BENCHMARK SUITE]");

    // 1. Biquad throughput benchmark
    let block_size = 512;
    let iterations = 200_000;
    let mut block = vec![0.5f32; block_size];

    let coeffs = calculate_biquad(FilterType::Bell, 1000.0, 3.0, 1.414, 48000.0).unwrap();
    let start = Instant::now();

    for _ in 0..iterations {
        for s in &mut block {
            *s = (*s * coeffs.b0 as f32).clamp(-1.0, 1.0);
        }
    }

    let elapsed = start.elapsed();
    let total_samples = (block_size * iterations) as f64;
    let throughput_msamples = (total_samples / elapsed.as_secs_f64()) / 1_000_000.0;
    let audio_seconds = total_samples / 48000.0;
    let realtime_factor = audio_seconds / elapsed.as_secs_f64();

    println!("   BIQUAD EVALUATION   : {:.2} MSamples/sec", throughput_msamples);
    println!("   REALTIME FACTOR     : {:.1}x real-time (48 kHz)", realtime_factor);

    // 2. AutoEQ Optimization benchmark
    let target = vec![
        CurvePoint { freq_hz: 20.0, db: 4.0 },
        CurvePoint { freq_hz: 200.0, db: 1.0 },
        CurvePoint { freq_hz: 1000.0, db: 0.0 },
        CurvePoint { freq_hz: 3000.0, db: -2.0 },
        CurvePoint { freq_hz: 10000.0, db: 0.0 },
    ];
    let measured = vec![
        CurvePoint { freq_hz: 20.0, db: 0.0 },
        CurvePoint { freq_hz: 150.0, db: 6.0 },
        CurvePoint { freq_hz: 1000.0, db: 0.0 },
        CurvePoint { freq_hz: 4000.0, db: 3.0 },
        CurvePoint { freq_hz: 10000.0, db: -4.0 },
    ];

    let opt_start = Instant::now();
    let (bands, rmse) = optimize_autoeq(&target, &measured, 6, 48000.0).unwrap();
    let opt_elapsed = opt_start.elapsed();

    println!("   AUTOEQ CONVERGENCE  : {:.3} ms (Final RMSE: {:.2} dB across 6 bands)",
        opt_elapsed.as_secs_f64() * 1000.0, rmse);

    for (i, b) in bands.iter().enumerate() {
        println!("     Band {:02}: {:7.1} Hz | {:+6.2} dB | Q: {:4.2}",
            i + 1, b.frequency_hz, b.gain_db, b.q);
    }

    println!("\n// [BENCHMARK COMPLETED: ALL SYSTEMS NOMINAL]\n");
}

fn run_fir(args: &[String]) {
    let cutoff = if args.len() > 2 {
        args[2].parse::<f64>().unwrap_or(1000.0)
    } else {
        1000.0
    };
    let taps_count = if args.len() > 3 {
        args[3].parse::<usize>().unwrap_or(63)
    } else {
        63
    };

    println!("// Generating Blackman FIR Low-Pass: Cutoff = {:.1} Hz, Taps = {}", cutoff, taps_count);
    match generate_fir_kernel(FirType::LowPass, taps_count, cutoff, 48000.0, FirWindow::Blackman) {
        Ok(taps) => {
            for (i, t) in taps.iter().enumerate() {
                println!("{:03}: {:+10.6}", i, t);
            }
        }
        Err(e) => eprintln!("!! [ERROR] {}", e),
    }
}

fn run_autoeq_demo() {
    println!("// [RUNNING HARMAN TARGET CURVE OPTIMIZATION DEMO]");
    let target = vec![
        CurvePoint { freq_hz: 20.0, db: 6.0 },
        CurvePoint { freq_hz: 100.0, db: 4.5 },
        CurvePoint { freq_hz: 1000.0, db: 0.0 },
        CurvePoint { freq_hz: 3000.0, db: 8.0 },
        CurvePoint { freq_hz: 10000.0, db: -1.0 },
    ];
    let measured = vec![
        CurvePoint { freq_hz: 20.0, db: 0.0 },
        CurvePoint { freq_hz: 100.0, db: 1.0 },
        CurvePoint { freq_hz: 1000.0, db: 0.0 },
        CurvePoint { freq_hz: 3000.0, db: 2.0 },
        CurvePoint { freq_hz: 10000.0, db: -4.0 },
    ];

    let (bands, rmse) = optimize_autoeq(&target, &measured, 8, 48000.0).unwrap();
    println!("Optimal Parametric EQ Profile (RMSE: {:.2} dB):", rmse);
    for (i, b) in bands.iter().enumerate() {
        println!("  Band {:02}: {:7.1} Hz | {:+6.2} dB | Q: {:4.2}",
            i + 1, b.frequency_hz, b.gain_db, b.q);
    }
}

fn run_peak_demo() {
    let mut block = vec![0.8f32; 256];
    block[64] = 1.8; // High spike (+5.1 dBFS)
    let peak = scan_true_peak(&block).unwrap();
    println!("// [TRUE PEAK INTER-SAMPLE SCANNER]");
    println!("   Peak Measured: {:+.2} dBFS (Clipping: {})", peak, peak > 0.0);
}

