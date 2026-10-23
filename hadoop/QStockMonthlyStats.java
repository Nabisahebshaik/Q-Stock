// Hadoop MapReduce job: per (market, ticker, month) aggregation of daily data.
//
// Input : CSV with header  market,ticker,date,open,high,low,close,volume,log_ret
// Output: market \t ticker \t yyyy-MM \t n_days \t month_log_ret \t mean_log_ret
//         \t realized_vol_ann \t total_volume
//
// Mapper emits a partial aggregate "n,sum,sumsq,volume" per row; the combiner
// merges partials on the map side; the reducer merges and finalises.
// Written for Java 7 / Hadoop 2.6 (CDH 5.13).

import java.io.IOException;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;

public class QStockMonthlyStats {

  public static class StatsMapper extends Mapper<LongWritable, Text, Text, Text> {
    private final Text outKey = new Text();
    private final Text outVal = new Text();

    @Override
    protected void map(LongWritable offset, Text line, Context ctx)
        throws IOException, InterruptedException {
      String s = line.toString();
      if (s.startsWith("market,") || s.isEmpty()) return;          // header / blank
      String[] f = s.split(",", -1);
      if (f.length < 9 || f[8].isEmpty() || f[8].equals("NA")) {   // first day has no return
        ctx.getCounter("qstock", "skipped_rows").increment(1);
        return;
      }
      double r = Double.parseDouble(f[8]);
      double vol = (f[7].isEmpty() || f[7].equals("NA")) ? 0.0 : Double.parseDouble(f[7]);
      outKey.set(f[0] + "\t" + f[1] + "\t" + f[2].substring(0, 7));
      outVal.set("1," + r + "," + (r * r) + "," + vol);
      ctx.write(outKey, outVal);
      ctx.getCounter("qstock", "mapped_rows").increment(1);
    }
  }

  static double[] merge(Iterable<Text> values) {
    double[] acc = new double[4];
    for (Text v : values) {
      String[] p = v.toString().split(",");
      for (int i = 0; i < 4; i++) acc[i] += Double.parseDouble(p[i]);
    }
    return acc;
  }

  public static class StatsCombiner extends Reducer<Text, Text, Text, Text> {
    @Override
    protected void reduce(Text key, Iterable<Text> values, Context ctx)
        throws IOException, InterruptedException {
      double[] a = merge(values);
      ctx.write(key, new Text((long) a[0] + "," + a[1] + "," + a[2] + "," + a[3]));
    }
  }

  public static class StatsReducer extends Reducer<Text, Text, Text, Text> {
    @Override
    protected void reduce(Text key, Iterable<Text> values, Context ctx)
        throws IOException, InterruptedException {
      double[] a = merge(values);
      long n = (long) a[0];
      double mean = a[1] / n;
      double var = n > 1 ? (a[2] - n * mean * mean) / (n - 1) : 0.0;
      double volAnn = Math.sqrt(Math.max(var, 0.0) * 252.0);
      ctx.write(key, new Text(n + "\t" + a[1] + "\t" + mean + "\t" + volAnn + "\t" + (long) a[3]));
    }
  }

  public static void main(String[] args) throws Exception {
    if (args.length != 2) {
      System.err.println("usage: QStockMonthlyStats <input> <output>");
      System.exit(2);
    }
    Configuration conf = new Configuration();
    conf.set("mapreduce.output.textoutputformat.separator", "\t");
    Job job = Job.getInstance(conf, "qstock-monthly-stats");
    job.setJarByClass(QStockMonthlyStats.class);
    job.setMapperClass(StatsMapper.class);
    job.setCombinerClass(StatsCombiner.class);
    job.setReducerClass(StatsReducer.class);
    job.setNumReduceTasks(2);
    job.setOutputKeyClass(Text.class);
    job.setOutputValueClass(Text.class);
    FileInputFormat.addInputPath(job, new Path(args[0]));
    FileOutputFormat.setOutputPath(job, new Path(args[1]));
    System.exit(job.waitForCompletion(true) ? 0 : 1);
  }
}
